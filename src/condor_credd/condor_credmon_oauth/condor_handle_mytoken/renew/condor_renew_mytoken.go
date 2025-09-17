package main

import (
    "fmt"
    "strings"
    "os"
    "github.com/nogproject/nog/backend/pkg/pwd"
    renewal "condor_handle_mytoken/utils"
)

func main() {

    if len(os.Args) != 2 {
        fmt.Printf("Please specify the issuer(s). \n")
	fmt.Printf("Issuer(s) should be specified as a comma separated list. \n")
        os.Exit(1)
    }

    //-- retrieve actual issuer name(s)
    actual_issuer_name := os.Args[1]
    list_actual_issuer_name := []string{}
    var info_actual_issuer_name string

    //-- retrieve user name
    user_name := renewal.Convert_Name(pwd.Getpwuid(uint32(os.Getuid())).Name)

    if strings.Contains(actual_issuer_name,",") {
        list_actual_issuer_name = strings.Split(actual_issuer_name, ",")
        info_actual_issuer_name = strings.ReplaceAll(actual_issuer_name, "," , ", ")
        index := strings.LastIndex(info_actual_issuer_name, ", ")
        info_actual_issuer_name = info_actual_issuer_name[:index] + " and " + info_actual_issuer_name[index+len(", "):]
    } else {
        list_actual_issuer_name = append(list_actual_issuer_name, actual_issuer_name)
        info_actual_issuer_name = actual_issuer_name
    }

    fmt.Printf("\n")
    fmt.Printf("Hello %s! You are going to renew your credential(s) for the issuer(s) %s. \n\n", user_name, info_actual_issuer_name)

    tokendata := new(renewal.TokenData)

    //-- loop over actual issuer name(s)
    for i := 0; i < len(list_actual_issuer_name); i++ {

        renewal.Configure(tokendata, list_actual_issuer_name[i], "STANDALONE")
        renewal.Get_encryption_key(tokendata)

        //-- Only perform renewal if a credential directory exists
        //-- Remove and revoke existing credentials
        renewal.Prepare_renewal(tokendata)

        //-- mytoken generation
        renewal.Create_mytoken(tokendata)
        renewal.Encrypt_mytoken(tokendata)
        renewal.Write_token(tokendata,"top")

        //-- access token generation
        renewal.Create_access_token(tokendata)
        renewal.Write_token(tokendata,"use")

        renewal.Lifetime(tokendata)
        fmt.Printf("Your credential has been successfully renewed! \n\n")
        fmt.Printf("Its remaining life time is %s.\n\n",tokendata.Mytoken_time_dhs)
    }
}
