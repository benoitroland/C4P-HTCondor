exports.handler = function( event, context, callback ) {
	console.log( "Received request:\n", JSON.stringify( event ) );

	var spotFleetRequestID = event.SpotFleetRequestID;
	if(! spotFleetRequestID) {
		console.log( "Failed to find Spot Fleet request ID." );
		callback( "Failed to find Spot Fleet request ID." );
		return;
	}
	console.log( "Found Spot Fleet request ID: " + spotFleetRequestID );

	var ruleID = event.RuleID;
	if(! ruleID) {
		console.log( "Failed to find rule ID." );
		callback( "Failed to find rule ID." );
		return;
	}
	console.log( "Found rule ID: " + ruleID );

	var targetID = event.TargetID;
	if(! targetID) {
		console.log( "Failed to find target ID." );
		callback( "Failed to find target ID." );
		return;
	}
	console.log( "Found target ID: " + targetID );

	var leaseExpiration = event.LeaseExpiration;
	if(! leaseExpiration) {
		console.log( "Failed to find lease expiration." );
		callback( "Failed to find lease expiration." );
		return;
	}
	console.log( "Found lease expiration: " + leaseExpiration );

	var timestamp = Math.floor( Date.now() / 1000 );
	if( timestamp <= leaseExpiration ) {
		console.log( "Lease has not expired yet (" + timestamp + " <= " + leaseExpiration + ")." )
		callback( null );
		return;
	}
	console.log( "Lease has expired: " + timestamp + " > " + leaseExpiration + "." )

	var AWS = require( 'aws-sdk' );
	var ec2 = new AWS.EC2();

	// Assumes we have fewer than 1000 SFRs.
	var p = { };
	ec2.describeSpotFleetRequests( p, function( err, data ) {
		var spotFleetRequestIDs = [];

		if( err ) {
			console.log( err, err.stack );
			callback( err, err.stack );
		} else {
			for( var i = 0; i < data.SpotFleetRequestConfigs.length; ++i ) {
				var config = data.SpotFleetRequestConfigs[i];
				var sfrc = config.SpotFleetRequestConfig;
				if( sfrc.ClientToken.startsWith( spotFleetRequestID ) ) {
					// spotFleetRequestID = config.SpotFleetRequestId;
					spotFleetRequestIDs.push( config.SpotFleetRequestId );
					break;
				}
			}


	var params = {
		// SpotFleetRequestIds : [ spotFleetRequestID ],
		SpotFleetRequestIds : spotFleetRequestIDs,
		TerminateInstances : true
	};
	ec2.cancelSpotFleetRequests( params, function( err, data ) {
		// cancelSpotFleetRequests() always succeeds.  *sigh*
		if( data.UnsuccessfulFleetRequests.length != 0 ) {
			console.log( "Failed to cancel Spot Fleet request." );
			callback( "Failed to cancel Spot Fleet request.", data );
		} else {
			console.log( "Succesfully cancelled Spot Fleet request." );

			var cwe = new AWS.CloudWatchEvents();
			var params = {
				Rule : ruleID,
				Ids : [ targetID ]
			};
			console.log( "Attempting to remove targets: ", params );
			cwe.removeTargets( params, function( err, data ) {
				// It is not an error to fail to remove a target that
				// doesn't exist.  *sigh*
				if( err || data == null || data.FailedEntries.length != 0 ) {
					console.log( "Failed to remove targets." );
					if( err ) {
						callback( err, err.stack );
					} else {
						callback( "Failed to remove targets.", data )
					}
				} else {
					console.log( "Successfully removed targets.", data );
					var params = { Name : ruleID }
					// It's OK for this to fail if it's got targets we
					// weren't told about.  We could check for that and
					// clean up our output if the daemon ever starts
					// using multiple targets per event.
					cwe.deleteRule( params, function( err, data ) {
						if( err ) {
							console.log( err, err.stack );
							callback( err, err.stack );
						} else {
							console.log( "Succesfully deleted event." );
							callback( null, "Successfully deleted event." );
						}
					});
				}
			});
		}
	});


		}
	});
}
