package main

import (
    "fmt"
    "flag"
    "strings"
    "os"
    "os/user"
    producer "producer_mytoken/utils"
)

func main() {

    //-- usage
    flag.Usage = func() {
        fmt.Printf("Usage: %s [optional parameters] \n\n", os.Args[0])

        fmt.Printf("Optional parameters: \n\n")

        flag.PrintDefaults()

        fmt.Printf("\nExamples: \n\n")
        fmt.Printf("  %s -issuer helmholtz,iam-ildg -email alice@example.com \n", os.Args[0])
        fmt.Printf("  %s -email alice@example.com \n", os.Args[0])
        fmt.Printf("  %s \n", os.Args[0])
    }

    //-- retrieve actual issuer name(s), email and use case
    actual_issuer_name_ptr := flag.String("issuer", "helmholtz", "comma-separated list of issuers to be used")
    email_user_ptr := flag.String("email", "undefined", "notification email address")
    use_case_ptr := flag.String("use_case", "STANDALONE", "HTCONDOR or STANDALONE")

    flag.Parse()

    actual_issuer_name := *actual_issuer_name_ptr
    email_user := *email_user_ptr
    use_case := *use_case_ptr

    if use_case != "HTCONDOR" && use_case != "STANDALONE" {
        fmt.Printf("\nThe use case \"%s\" specified in your command line does not exist! \n", use_case)
        os.Exit(1)
    }

    //-- retrieve user name
    current_user, _ := user.Current()
    user_name := producer.Convert_Name(current_user.Username)

    //-- producer issuer name(s)
    list_actual_issuer_name := []string{}
    var info_actual_issuer_name string

    if strings.Contains(actual_issuer_name,",") {
        list_actual_issuer_name = strings.Split(actual_issuer_name, ",")
	info_actual_issuer_name = strings.ReplaceAll(actual_issuer_name, "," , ", ")
	index := strings.LastIndex(info_actual_issuer_name, ", ")
	info_actual_issuer_name = info_actual_issuer_name[:index] + " and " + info_actual_issuer_name[index+len(", "):]
    } else {
        list_actual_issuer_name = append(list_actual_issuer_name, actual_issuer_name)
        info_actual_issuer_name = actual_issuer_name
    }

    //-- use case
    if use_case == "HTCONDOR" {
        fmt.Printf("\n\n")
        fmt.Printf("Hello %s! You are going to submit your HTCondor job(s) using the issuer(s) %s. \n\n", user_name, info_actual_issuer_name)
    } else if use_case == "STANDALONE" {
        fmt.Printf("\n\n")
        fmt.Printf("Hello %s! You are going to produce or renew your credential(s) using the issuer(s) %s. \n\n", user_name, info_actual_issuer_name)
    }

    //-- email
    if email_user == "undefined" {
        if use_case == "HTCONDOR" {
            fmt.Printf("You have not specified an email address to be notified about the status of your job(s) and credential(s). \n\n")
	} else if use_case == "STANDALONE" {
	    fmt.Printf("You have not specified an email address to be notified about the status of your credential(s). \n\n")
	}
    } else {
        if use_case == "HTCONDOR" {
            fmt.Printf("You will be notified about the status of your job(s) and credential(s) using the email address %s. \n\n", email_user)
	 } else if use_case == "STANDALONE" {
	     fmt.Printf("You will be notified about the status of your credential(s) using the email address %s. \n\n", email_user)
         }
    }

    tokendata := new(producer.TokenData)

    //-- loop over actual issuer name(s)
    for i := 0; i < len(list_actual_issuer_name); i++ {

        producer.Configure(tokendata, list_actual_issuer_name[i], use_case)
        producer.Get_encryption_key(tokendata)

        //-- Produce or renew credentials
        if producer.Renew(tokendata, use_case) {

            //-- user credential directory
            producer.Create_credential_dir(tokendata)

            //-- mytoken generation
            producer.Create_mytoken(tokendata)
            producer.Encrypt_mytoken(tokendata)
            producer.Write_token(tokendata,"top")

            //-- access token generation
            producer.Create_access_token(tokendata)
            producer.Write_token(tokendata,"use")

            //-- life time information
            producer.Lifetime(tokendata)

	    if use_case == "HTCONDOR" {
	        fmt.Printf("Your credential has been successfully created! \n\n")
            } else if use_case == "STANDALONE" {
	        fmt.Printf("Your credential has been successfully created or renewed! \n\n")
            }

	    fmt.Printf("Its remaining life time is %s.\n\n",tokendata.Mytoken_time_dhs)
        }
    }

    //-- email
    producer.Write_email(tokendata, email_user)

}