#include "condor_common.h"
#include "condor_debug.h"
#include "condor_config.h"

#include <filesystem>
#include <algorithm>

#include "spooled_job_files.h"
#include "scheduler.h"
#include "qmgmt.h"

int
Scheduler::checkpointCleanUpReaper( int pid, int status ) {
	// If the clean-up plug-in succeeded, remove the job's spool directory?
	// (We'd need to determine it before spawning the plug-in and store the
	// result, because we won't have ready access to the job ad by the time
	// the plug-in finishes.  I'm tempted to say that the plug-in deletes
	// MANIFEST files after it finishes deleting their contents, and that
	// preen will take care of deleting the empty directories.)

	dprintf( D_ZKM, "checkpoint clean-up proc %d returned %d\n", pid, status );
	return 0;
}

bool
Scheduler::doCheckpointCleanUp( int cluster, int proc, ClassAd * jobAd ) {
	// In case we ever want it.
	std::string error;

	std::string checkpointDestination;
	if(! jobAd->LookupString( ATTR_JOB_CHECKPOINT_DESTINATION, checkpointDestination ) ) {
		return true;
	}


	// This dprintf(), and all subsequent ones in this function, should
	// probably preface themselves with 'doCheckpointCleanup(): '.
	dprintf( D_ZKM, "Cleaning up checkpoint of job %d.%d...\n", cluster, proc );

	//
	// Create a subprocess to invoke the deletion plug-in.  Its
	// reaper will call JobIsFinished() and JobIsFinishedDone().
	//
	// The call will be
	//
	// `/full/path/to/condor_manifest deleteFilesStoredAt
	//      /full/path/to/protocol-specific-clean-up-plug-in
	//      checkpointDestination/globalJobID
	//      /full/path/to/manifest-file-trailing-checkpoint-number
	//      lowCheckpointNo highCheckpointNo`
	//
	// Moving the iteration over checkpoint numbers into condor_manifest
	// means that we don't have to worry about spawning more than one
	// process here (because of ARG_MAX limitations).
	//

	static int cleanup_reaper_id = -1;
	if( cleanup_reaper_id == -1 ) {
		cleanup_reaper_id = daemonCore->Register_Reaper(
			"externally-stored checkpoint reaper",
			(ReaperHandlercpp) & Scheduler::checkpointCleanUpReaper,
			"externally-stored checkpoint reaper",
			this
		);
	}


	// Determine and validate `full/path/to/condor_manifest`.
	std::string binPath;
	param( binPath, "BIN" );
	std::filesystem::path BIN( binPath );
	std::filesystem::path condor_manifest = BIN / "condor_manifest";
	if(! std::filesystem::exists(condor_manifest)) {
		formatstr( error, "'%s' does not exist, aborting", condor_manifest.string().c_str() );
		dprintf( D_ZKM, "%s\n", error.c_str() );
		return false;
	}


	// Determine and validate `full/path/to/protocol-specific-clean-up-plug-in`.
	std::string protocol = checkpointDestination.substr( 0, checkpointDestination.find( "://" ) );
	if( protocol == checkpointDestination ) {
		formatstr( error,
			"Invalid checkpoint destination (%s) in checkpoint clean-up attempt should be impossible, aborting.",
			checkpointDestination.c_str()
		);
		dprintf( D_ALWAYS, "%s\n", error.c_str() );
		return false;
	}

	std::string cleanupPluginConfigKey;
	formatstr( cleanupPluginConfigKey, "%s_CLEANUP_PLUGIN", protocol.c_str() );
	std::string destinationSpecificBinary;
	param( destinationSpecificBinary, cleanupPluginConfigKey.c_str() );
	if(! std::filesystem::exists( destinationSpecificBinary )) {
		formatstr( error,
			"Clean-up plug-in for '%s' (%s) does not exist, aborting",
			protocol.c_str(), destinationSpecificBinary.c_str()
		);
		dprintf( D_ALWAYS, "%s\n", error.c_str() );
		return false;
	}


	//
	// The schedd stores spooled files in a directory tree whose first branch
	// is the job's cluster ID modulo 1000.  This means that only the schedd
	// can safely remove that directory; any other process might remove it
	// between when the schedd checks for its existence and when it tries to
	// create the next subdirectory.  So we rename the job-specific directory
	// out of the way.
	//
	dprintf( D_ZKM, "Renaming job (%d.%d) spool directory to permit cleanup.\n", cluster, proc );

	std::string spoolPath;
	SpooledJobFiles::getJobSpoolPath( jobAd, spoolPath );
	std::filesystem::path spool( spoolPath );

	std::filesystem::path SPOOL = spool.parent_path().parent_path().parent_path();
	std::filesystem::path checkpointCleanup = SPOOL / "checkpoint-cleanup";
	std::filesystem::path target_dir = checkpointCleanup / spool.filename();

	std::error_code errCode;
	if( std::filesystem::exists( checkpointCleanup ) ) {
		if(! std::filesystem::is_directory( checkpointCleanup )) {
			dprintf( D_ALWAYS, "'%s' is a file and needs to be a directory in order to do checkpoint cleanup.\n", checkpointCleanup.string().c_str() );
			return false;
		}
	} else {
		std::filesystem::create_directory( checkpointCleanup, SPOOL, errCode );
		if( errCode ) {
			dprintf( D_ALWAYS, "Failed to create checkpoint clean-up directory '%s' (%d: %s), will not clean up.\n", checkpointCleanup.string().c_str(), errCode.value(), errCode.message().c_str() );
			return false;
		}
	}

	dprintf( D_ZKM, "Renaming job (%d.%d) spool directory from '%s' to '%s'.\n", cluster, proc, spool.string().c_str(), target_dir.string().c_str() );
	std::filesystem::rename( spool, target_dir, errCode );
	if( errCode ) {
		dprintf( D_ALWAYS, "Failed to rename job (%d.%d) spool directory (%d: %s), will not clean up.\n", cluster, proc, errCode.value(), errCode.message().c_str() );
		return false;
	}


	// Drop a copy of the job ad into the directory in case this attempt
	// to clean up fails and we need to try it again later.
	std::filesystem::path jobAdPath = target_dir / ".job.ad";
	FILE * jobAdFile = safe_fopen_wrapper( jobAdPath.string().c_str(), "w" );
	if( jobAdFile == NULL ) {
		dprintf( D_ALWAYS, "Failed to open job ad file '%s'\n", jobAdPath.string().c_str() );
		return false;
	}
	fPrintAd( jobAdFile, * jobAd );
	fclose( jobAdFile );


	// We need this to construct the checkpoint-specific location.
	std::string globalJobID;
	if(! jobAd->LookupString( ATTR_GLOBAL_JOB_ID, globalJobID )) {
		error = "Failed to find global job ID in job ad, aborting";
		dprintf( D_ALWAYS, "%s\n", error.c_str() );
		return false;
	}
	std::replace( globalJobID.begin(), globalJobID.end(), '#', '_' );


	int checkpointNumber = -1;
	if(! jobAd->LookupInteger( ATTR_JOB_CHECKPOINT_NUMBER, checkpointNumber )) {
		error = "Failed to find checkpoint number in job ad, aborting";
		dprintf( D_ALWAYS, "%s\n", error.c_str() );
		return false;
	}

	std::string separator = "/";
	if( ends_with( checkpointDestination, "/" ) ) {
		separator = "";
	}


	std::string specificCheckpointDestination;

	std::vector< std::string > cleanup_process_args;
	cleanup_process_args.push_back( condor_manifest.string() );
	cleanup_process_args.push_back( "deleteFilesStoredAt" );
	cleanup_process_args.push_back( destinationSpecificBinary );

	// Construct the checkpoint-specific location prefix.
	formatstr(
		specificCheckpointDestination,
		"%s%s%s",
		checkpointDestination.c_str(), separator.c_str(), globalJobID.c_str()
	);

	// Construct the manifest file prefix.
	std::string manifestFileName = "_condor_checkpoint_MANIFEST";
	std::filesystem::path manifestFilePath = target_dir / manifestFileName;

	cleanup_process_args.push_back( specificCheckpointDestination );
	cleanup_process_args.push_back( manifestFilePath.string() );
	cleanup_process_args.push_back( "0" );

	std::string buffer;
	formatstr(buffer, "%d", checkpointNumber );
	cleanup_process_args.push_back( buffer );


	OptionalCreateProcessArgs cleanup_process_opts;
	auto pid = daemonCore->CreateProcessNew(
		condor_manifest.string(),
		cleanup_process_args,
		cleanup_process_opts.reaperID(cleanup_reaper_id)
	);


	dprintf( D_ZKM, "... checkpoint clean-up for job %d.%d spawned as pid %d.\n", cluster, proc, pid );
	return true;
}
