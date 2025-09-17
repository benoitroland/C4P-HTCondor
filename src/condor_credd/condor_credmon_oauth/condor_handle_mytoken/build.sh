#!/bin/bash
go build -o condor_producer_mytoken ./producer/condor_producer_mytoken.go
go build -o condor_renew_mytoken ./renew/condor_renew_mytoken.go
