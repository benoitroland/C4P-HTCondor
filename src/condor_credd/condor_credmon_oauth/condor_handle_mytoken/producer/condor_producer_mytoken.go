package main

import (
    "fmt"
    "strings"
    "os"
    "github.com/nogproject/nog/backend/pkg/pwd"
    producer "condor_handle_mytoken/utils"
)

func main() {

   var use_case string = "STANDALONE"
   var email_user string

   if len(os.Args) < 2 {
       fmt.Printf("Please specify the issuer(s) and the notification email for the credential(s) production in HTCondor. \n")
       fmt.Printf("Please specify the issuer(s) for the standalone credential(s) production. \n")
       fmt.Printf("Issuer(s) should be specified as a comma separated list. \n")
       os.Exit(1)
    }

    //-- retrieve actual issuer name(s)
    actual_issuer_name := os.Args[1]
    list_actual_issuer_name := []string{}
    var info_actual_issuer_name string

    //-- retrieve email and use case
    if len(os.Args) == 3 {
        use_case = "HTCONDOR"
	email_user = os.Args[2]
    }

    //-- retrieve user name
    user_name := producer.Convert_Name(pwd.Getpwuid(uint32(os.Getuid())).Name)

    if strings.Contains(actual_issuer_name,",") {
        list_actual_issuer_name = strings.Split(actual_issuer_name, ",")
	info_actual_issuer_name = strings.ReplaceAll(actual_issuer_name, "," , ", ")
	index := strings.LastIndex(info_actual_issuer_name, ", ")
	info_actual_issuer_name = info_actual_issuer_name[:index] + " and " + info_actual_issuer_name[index+len(", "):]
    } else {
        list_actual_issuer_name = append(list_actual_issuer_name, actual_issuer_name)
        info_actual_issuer_name = actual_issuer_name
    }

    if use_case == "HTCONDOR" {
        fmt.Printf("\n\n")
        fmt.Printf("Hello %s! You are going to submit your HTCondor job(s) using the issuer(s) %s. \n\n", user_name, info_actual_issuer_name)
    } else if use_case == "STANDALONE" {
        fmt.Printf("\n")
        fmt.Printf("Hello %s! You are going to produce your credential(s) for the issuer(s) %s. \n\n", user_name, info_actual_issuer_name)
    }

    if use_case == "HTCONDOR" {
        if email_user == "empty" {
	    fmt.Printf("You do not have specified an email address to be notified about the status of your job(s) and credential(s). \n\n")
        } else if email_user == "wrong" {
            fmt.Printf("The email address you have specified does not seem to be correct! \n\n")
        } else {
            fmt.Printf("You will be notified about the status of your job(s) and credential(s) using the email address %s. \n\n", email_user)
        }
    }

    tokendata := new(producer.TokenData)

    //-- loop over actual issuer name(s)
    for i := 0; i < len(list_actual_issuer_name); i++ {

        producer.Configure(tokendata, list_actual_issuer_name[i], use_case)
        producer.Get_encryption_key(tokendata)

        //-- Produce or renew credentials if needed
        if producer.Renew(tokendata) {

            //-- user credential directory
            producer.Create_credential_dir(tokendata)

            //-- mytoken generation
            producer.Create_mytoken(tokendata)
            producer.Encrypt_mytoken(tokendata)
            producer.Write_token(tokendata,"top")

            //-- access token generation
            producer.Create_access_token(tokendata)
            producer.Write_token(tokendata,"use")
	    producer.Lifetime(tokendata)
	    fmt.Printf("Your credential has been successfully created! \n\n")
	    fmt.Printf("Its remaining life time is %s.\n\n",tokendata.Mytoken_time_dhs)
        }
    }

    //-- email
    if use_case == "HTCONDOR" {
        producer.Write_email(tokendata,email_user)
    }
}