#!/usr/bin/env pytest

#Job Ad attribute: JobSubmitMethod assignment testing
#
#Each sub-test submits job(s) and waits till all are hopefully finished.
#Then it collects the recent job ads from schedd history and returns
#them for evaluation.
#
#Written by: Cole Bollig @ March 2022

from ornithology import *
import os
from time import sleep


#Fixture to write simple .sub file for general use
@action
def write_sub_file(test_dir,path_to_sleep):
     submit_file = open( test_dir / "simple_submit.sub","w")
     submit_file.write("""executable={0}
arguments=1
should_transfer_files=Yes
queue
""".format(path_to_sleep))
     submit_file.close()
     return test_dir / "simple_submit.sub"

#Fixture to write simple .dag file using write_sub_file fixture for general dag use
@action
def write_dag_file(test_dir,write_sub_file):
     dag_file = open( test_dir / "simple.dag", "w")
     dag_file.write("""JOB A {0}
JOB B {0}

PARENT A CHILD B
""".format(write_sub_file))
     dag_file.close()
     return test_dir / "simple.dag"

#Fixture to run condor_submit and check the JobSubmitMethod attr
@action
def run_condor_submit(default_condor,write_sub_file):
     #Submit job
     p = default_condor.run_command(["condor_submit", write_sub_file])
     sleep(10)
     #Get the job ad for completed job
     schedd = default_condor.get_local_schedd()
     job_ad = schedd.history(
          constraint=None,
          projection=["JobSubmitMethod"],
          match=1,
     )
     
     return job_ad

#Fixture to run condor_submit_dag and check the JobSubmitMethod attr
@action
def run_dagman_submission(default_condor,write_dag_file):
     #Submit job 
     p = default_condor.run_command(["condor_submit_dag",write_dag_file])
     sleep(20)
     #Get the job ad for completed job
     schedd = default_condor.get_local_schedd()
     job_ad = schedd.history(
          constraint=None,
          projection=["JobSubmitMethod"],
          match=3,
     )
     
     return job_ad

subTestNum = 0
#Fixture to run python bindings with and without user set value and check the JobSubmitMethod attr
@action(params={"normal":'',"user_set":"job.setSubmitMethod(6)"})#Add line to have setting JobSubmitMethod to value 6 in python files
def run_python_bindings(default_condor,test_dir,path_to_sleep,request):
     global subTestNum
     filename = "test{}.py".format(subTestNum)
     python_file = open(test_dir / filename, "w")
     subTestNum += 1
     python_file.write(
     """import htcondor
import classad

job = htcondor.Submit({{
     "executable":"{0}"
}})

{1}
schedd = htcondor.Schedd()
submit_result = schedd.submit(job)
print(job.getSubmitMethod())
""".format(path_to_sleep,request.param))
     python_file.close()
     #^^^Make python file for submission^^^

     #Submit file to run job
     p = default_condor.run_command(["python3",test_dir / filename])

     return p

#Fixture to run 'htcondor job submit' and check the JobSubmitMethod attr
@action
def run_htcondor_job_submit(default_condor,write_sub_file):
     p = default_condor.run_command(["htcondor","job","submit",write_sub_file])
     sleep(10)
     #Get the job ad for completed job
     schedd = default_condor.get_local_schedd()
     job_ad = schedd.history(
          constraint=None,
          projection=["JobSubmitMethod"],
          match=1,
     )
     
     return job_ad

#Fixture to run 'htcondor jobset submit' and check the JobSubmitMethod attr
@action
def run_htcondor_jobset_submit(default_condor,test_dir,path_to_sleep):
     jobset_file = open(test_dir / "job.set", "w")
     jobset_file.write(
     """name = JobSubmitMethodTest

iterator = table var {{
     Job1
     Job2
}}

job {{
     executable = {}
     queue
}}
""".format(path_to_sleep))
     jobset_file.close()

     p = default_condor.run_command(["htcondor","jobset","submit",test_dir / "job.set"])
     sleep(10)
     #Get the job ad for completed job
     schedd = default_condor.get_local_schedd()
     job_ad = schedd.history(
          constraint=f"JobSetName == \"JobSubmitMethodTest\"",
          projection=["JobSubmitMethod"],
          match=2,
     )
     
     return job_ad

#Fixture to run 'htcondor dag submit' and check the JobSubmitMethod attr
@action
def run_htcondor_dag_submit(default_condor,write_dag_file,test_dir):
     #List of files needed to be moved
     files_to_move = ["simple.dag.condor.sub","simple.dag.dagman.log","simple.dag.dagman.out","simple.dag.lib.err","simple.dag.lib.out","simple.dag.metrics","simple.dag.nodes.log"]
     #make directories for each dag submission test to avoid errors
     p = default_condor.run_command(["pwd"])
     p = default_condor.run_command(["mkdir",test_dir / "dag_test1"])
     p = default_condor.run_command(["mkdir",test_dir / "dag_test2"])
     #move first test files into dag_test1 directory
     for name in files_to_move:
          p = default_condor.run_command(["mv",test_dir / name, test_dir / "dag_test1"])
     #run second dag submission test 
     p = default_condor.run_command(["htcondor","dag","submit", write_dag_file])
     sleep(20)
     #move secodn test files into dag_test2 directory
     for name in files_to_move:
          p = default_condor.run_command(["mv",test_dir / name, test_dir / "dag_test1"])
     #Get the job ad for completed job
     schedd = default_condor.get_local_schedd()
     job_ad = schedd.history(
          constraint=None,
          projection=["JobSubmitMethod"],
          match=3,
     )
     
     return job_ad


#JobSubmitMethod Tests
class TestJobSubmitMethod:

     #Test condor_submit yields 0
     def test_condor_submit_method_value(self,run_condor_submit):
          i = 0
          passed = False
          #Check that returned job ads have a submission value of 0
          for ad in run_condor_submit:
               i += 1
               #If job ad submit method is not 0 then fail test
               if ad["JobSubmitMethod"] == 0:
                    passed = True
          if i != 1:
               passed = False
          #If made it this far then the test passed
          assert passed

     #Test condor_submit yields 0 for dag and 1 for dag submitted jobs
     def test_dagman_submit_job_value(self,run_dagman_submission):
          countDAG = 0
          countJobs = 0
          passed = False
          #Check that returned job ads 
          for ad in run_dagman_submission:
               if ad["JobSubmitMethod"] == 0:
                    countDAG += 1
               if ad["JobSubmitMethod"] == 1:
                    countJobs += 1
          if countDAG == 1 and countJobs == 2:
               passed = True

          #If made it this far then the test passed
          assert passed

     #Test python bindings job submission yields 2 for normal submission and 6 for when a user sets the value to 6
     def test_python_bindings_submit_method_value(self,run_python_bindings):
          passed = False
          if run_python_bindings.stdout == '2':
               passed = True
          elif run_python_bindings.stdout == '6':
               passed = True
          assert passed

     #Test 'htcondor job submit' yields 3
     def test_htcondor_job_submit_method_value(self,run_htcondor_job_submit):
          i = 0
          passed = False
          #Check that returned job ads have a submission value of 3
          for ad in run_htcondor_job_submit:
               i += 1
               #If job ad submit method is not 3 then fail test
               if ad["JobSubmitMethod"] == 3:
                    passed = True
          if i != 1:
               passed = False
          #If made it this far then the test passed
          assert passed

     #Test 'htcondor jobset submit yields 4
     def test_htcondor_jobset_submit_method_value(self,run_htcondor_jobset_submit):
          i = 0
          passed = False
          #Check that returned job ads have a submission value of 4
          for ad in run_htcondor_jobset_submit:
               i += 1
               #If job ad submit method is not 4 then fail test
               if ad["JobSubmitMethod"] == 4:
                    passed = True
          if i != 2:
               passed = False
          #If made it this far then the test passed
          assert passed

     #Test 'htcondor dag submit yields 5
     def test_htcondor_dag_submit_method_value(self,run_htcondor_dag_submit):
          countDAG = 0
          countJobs = 0
          passed = False
          #Check that returned job ads 
          for ad in run_htcondor_dag_submit:
               if ad["JobSubmitMethod"] == 5:
                    countDAG += 1
               if ad["JobSubmitMethod"] == 1:
                    countJobs += 1
          if countDAG == 1 and countJobs == 2:
               passed = True

          #If made it this far then the test passed
          assert passed



