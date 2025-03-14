package main

import (
    "fmt"
    "strings"
    "os"
    "github.com/nogproject/nog/backend/pkg/pwd"
    producer "condor_producer_mytoken/mytokenproducer"
)

func main() {

    //-- retrieve actual issuer name(s)
    if len(os.Args) != 2 {
        fmt.Printf("Please specify the AAI provider(s). \n")
        os.Exit(1)
    }

    actual_issuer_name := os.Args[1]
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

    fmt.Printf("\n\n")
    fmt.Printf("Hello %s! You are going to submit your HTCondor job(s) using the issuer(s) %s. \n\n", pwd.Getpwuid(uint32(os.Getuid())).Name, info_actual_issuer_name)

    //-- loop over actual issuer name(s)
    for i := 0; i < len(list_actual_issuer_name); i++ {

        tokendata := new(producer.TokenData)
        producer.Configure(tokendata, list_actual_issuer_name[i])
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
}
