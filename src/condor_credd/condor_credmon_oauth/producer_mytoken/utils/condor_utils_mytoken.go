package mytokenproducer

import (
    "fmt"
    "os"
    "time"
    "strings"
    "bufio"
    "io"
    "io/ioutil"
    "github.com/golang-jwt/jwt"
    "github.com/hako/durafmt"
    mytokenlib "github.com/oidc-mytoken/lib"
    api "github.com/oidc-mytoken/api/v0"
    fernet "github.com/fernet/fernet-go"
    "path/filepath"
    "strconv"
    "os/user"
    "os/exec"
    "syscall"
    "math"
    "unicode"
)

type TokenData struct {
    Encryption_key, Encryption_key_file string

    Oauth_issuer_url, Oauth_issuer_name string
    Mytoken_issuer_url, Mytoken_profile string
    Cred_dir, Cred_dir_user string

    Mytoken, Mytoken_encrypted, Mytoken_old, Mytoken_file string
    Mytoken_server *mytokenlib.MytokenServer

    Access_token, Access_token_file string

    Mytoken_time float64
    Mytoken_time_dhs *durafmt.Durafmt

    Email_file string
}

func Check(err error) {
    if err != nil {
        fmt.Printf("error: %s\n", err.Error())
        os.Exit(1)
    }
}

func PrintDebug(format string, a ...any) {
    log_level := Parameter("PRODUCER_OAUTH_DEBUG")
    if log_level == "DEBUG" {
        fmt.Printf(format, a...)
    }
 }

func Parameter(parameter string) string {
     var condor_config_file string = "/etc/condor/config.d/"
     var parameter_value string = "undefined"
     FindParameter(condor_config_file, parameter, &parameter_value)
     return parameter_value
}

func FindParameter(path_directory string, parameter_required string, parameter_value *string) {

    filepath.Walk(path_directory, func(filename string, info os.FileInfo, err error) error {

        if err != nil || len(filename) == 0 {
            return err
        }

        file, err := os.Open(filename)
        Check(err)

        defer file.Close()

        if !info.IsDir() && !strings.Contains(filename,"~") {

            reader := bufio.NewReader(file)

            for {

                line, err := reader.ReadString('\n')

                if equal := strings.Index(line, "="); equal >= 0 {
                    parameter := strings.TrimSpace(line[:equal-1])

                    if len(line) > equal {
                        if parameter == parameter_required {
                            *parameter_value = strings.TrimSpace(line[equal+1:])
                            break
                        }
                    }
                }

                if err == io.EOF {
                    break
                }

                Check(err)
            }
        }

        return nil
    })

    if *parameter_value == "undefined" {

        if condor_config_path, condor_config_err := exec.LookPath("condor_config_val"); condor_config_err == nil {
	    condor_config_cmd := exec.Command(condor_config_path, parameter_required)

            if condor_value , condor_value_error := condor_config_cmd.CombinedOutput(); condor_value_error == nil {
                *parameter_value = strings.TrimSpace(string(condor_value))
	    }
        }
    }

    if *parameter_value == "undefined" {
        fmt.Printf("Parameter %s not found! \n",parameter_required)
        fmt.Printf("Please define the parameter %s! \n", parameter_required)
        os.Exit(1)
    }
}

func Configure(tokendata *TokenData, actual_issuer_name string, use_case string) {

    fmt.Printf("Defining your credential for the issuer %s. \n\n", actual_issuer_name)

    tokendata.Encryption_key = "undefined"
    tokendata.Encryption_key_file = Parameter("SEC_ENCRYPTION_KEY_DIRECTORY")

    var is_actual_issuer_name bool = false

    oauth_issuer_url := Parameter("OAUTH_ISSUER_URL")
    oauth_issuer_name := Parameter("OAUTH_ISSUER_NAME")

    //-- multiple issuers are available
    if strings.Contains(oauth_issuer_name,",") {
        list_oauth_issuer_url := strings.Split(oauth_issuer_url, ",")
        list_oauth_issuer_name := strings.Split(oauth_issuer_name, ",")

        for i := 0; i < len(list_oauth_issuer_name); i++ {
            if list_oauth_issuer_name[i] == actual_issuer_name {
                tokendata.Oauth_issuer_url = list_oauth_issuer_url[i]
                tokendata.Oauth_issuer_name = list_oauth_issuer_name[i]
		is_actual_issuer_name = true
            }
        }

     //-- a single issuer is available
     } else if oauth_issuer_name == actual_issuer_name {
         tokendata.Oauth_issuer_url = oauth_issuer_url
         tokendata.Oauth_issuer_name = oauth_issuer_name
	 is_actual_issuer_name = true
    }

    //-- check if issuer is supported
    if !is_actual_issuer_name {
        if use_case == "HTCONDOR" {
            fmt.Printf("The issuer \"%s\" specified in your HTCondor job configuration file is not supported. \n", actual_issuer_name)
	} else if use_case == "STANDALONE" {
	    fmt.Printf("The issuer \"%s\" specified in your command line is not supported. \n", actual_issuer_name)
	}
        os.Exit(1)
    }

    tokendata.Mytoken_issuer_url = Parameter("MYTOKEN_ISSUER_URL")
    tokendata.Mytoken_profile = Parameter("MYTOKEN_PROFILE")

    current_user, _ := user.Current()

    tokendata.Cred_dir = Parameter("SEC_CREDENTIAL_DIRECTORY_OAUTH")
    tokendata.Cred_dir_user = tokendata.Cred_dir + "/" + current_user.Username

    tokendata.Mytoken = "undefined"
    tokendata.Mytoken_encrypted = "undefined"
    tokendata.Mytoken_old = "undefined"
    tokendata.Mytoken_file = tokendata.Cred_dir_user + "/" + tokendata.Oauth_issuer_name + ".top"

    server, err := mytokenlib.NewMytokenServer(tokendata.Mytoken_issuer_url)
    Check(err)
    tokendata.Mytoken_server = server

    tokendata.Access_token = "undefined"
    tokendata.Access_token_file = tokendata.Cred_dir_user + "/" + tokendata.Oauth_issuer_name + ".use"

    tokendata.Mytoken_time = 0

    tokendata.Email_file = tokendata.Cred_dir_user + "/email.txt"

    PrintDebug("Configuration successfully retrieved: \n\n")
    PrintDebug("OAUTH ISSUER URL: %s \n", tokendata.Oauth_issuer_url)
    PrintDebug("OAUTH ISSUER NAME: %s \n\n", tokendata.Oauth_issuer_name)
    PrintDebug("MYTOKEN ISSUER URL: %s \n", tokendata.Mytoken_issuer_url)
    PrintDebug("MYTOKEN PROFILE: %s \n\n", tokendata.Mytoken_profile)
    PrintDebug("CREDENTIAL DIRECTORY: %s \n", tokendata.Cred_dir)
    PrintDebug("USER CREDENTIAL DIRECTORY: %s \n\n", tokendata.Cred_dir_user)
    PrintDebug("MYTOKEN CREDENTIAL FILE: %s \n", tokendata.Mytoken_file)
    PrintDebug("ACCESS TOKEN CREDENTIAL FILE: %s \n", tokendata.Access_token_file)
    PrintDebug("EMAIL FILE: %s \n\n", tokendata.Email_file)
}

func Get_encryption_key(tokendata *TokenData) {
    key, err := os.ReadFile(tokendata.Encryption_key_file)
    tokendata.Encryption_key = string(key)
    Check(err)
    PrintDebug("Encryption key for Fernet algorithm successfully retrieved \n\n")
}

func Create_credential_dir(tokendata *TokenData) {
    current_user, _ := user.Current()
    if _, err := os.Stat(tokendata.Cred_dir_user); os.IsNotExist(err) {
        if err := os.Mkdir(tokendata.Cred_dir_user, os.FileMode(0770)); err == nil {
            PrintDebug("Credential directory successfully created for user %s: %s\n\n", current_user.Username, tokendata.Cred_dir_user)
        }
    } else {
        PrintDebug("Credential directory for user %s already exists: %s\n\n", current_user.Username, tokendata.Cred_dir_user)
    }

    info, _ := os.Stat(tokendata.Cred_dir_user)
    stat := info.Sys().(*syscall.Stat_t)

    uid := stat.Uid
    gid := stat.Gid

    uid_string := strconv.FormatUint(uint64(uid), 10)
    gid_string := strconv.FormatUint(uint64(gid), 10)

    user_info, _ := user.LookupId(uid_string)
    group_info, _ := user.LookupGroupId(gid_string)

    PrintDebug("Directory %s belongs to user: %s \n\n", tokendata.Cred_dir_user, user_info.Username)
    PrintDebug("Directory %s belongs to group: %s \n\n", tokendata.Cred_dir_user, group_info.Name)
}

func Create_mytoken(tokendata *TokenData) {

    htcondor_token_name := "mytoken-"
    htcondor_token_name += tokendata.Oauth_issuer_name

    Mytoken_request := api.GeneralMytokenRequest{
        Issuer: tokendata.Oauth_issuer_url,
        ApplicationName: "HTCondor job submission",
        Name: htcondor_token_name,
        IncludedProfiles: api.IncludedProfiles{tokendata.Mytoken_profile},
    }

    callbacks := mytokenlib.PollingCallbacks {

        Init: func(authorizationURL string) error {
            fmt.Printf("Please visit the following url in order to generate your credential: %s \n\n", authorizationURL)
            return nil
        },

        Callback: func(interval int64, iteration int) {
            if iteration == 0 {
                fmt.Printf("Starting polling and waiting for your approval ...")
                return
            }
            if int64(iteration)%(15/interval) == 0 {
                fmt.Printf("...")
            }
        },

        End: func() {
            fmt.Printf("\n\n")
            PrintDebug("Mytoken credential successfully created \n\n")
        },
    }

    Mytoken_endpoint := tokendata.Mytoken_server.Mytoken
    Mytoken_response, err := Mytoken_endpoint.APIFromAuthorizationFlowReq(Mytoken_request, callbacks)
    Check(err)
    tokendata.Mytoken = Mytoken_response.Mytoken
}

func Encrypt_mytoken(tokendata *TokenData) {
    key := fernet.MustDecodeKeys(tokendata.Encryption_key)
    if encrypted, err := fernet.EncryptAndSign([]byte(tokendata.Mytoken), key[0]); err == nil {
        tokendata.Mytoken_encrypted = string(encrypted)
        PrintDebug("Mytoken credential successfully encrypted \n\n")
    } else {
        Check(err)
    }
}

func Decrypt_mytoken(tokendata *TokenData) string {
    Mytoken_encrypted, err := os.ReadFile(tokendata.Mytoken_file)
    Check(err)

    key := fernet.MustDecodeKeys(tokendata.Encryption_key)
    Mytoken_decrypted := fernet.VerifyAndDecrypt([]byte(Mytoken_encrypted), 0*time.Second, key)
    return string(Mytoken_decrypted)
}

func Write_token(tokendata *TokenData, token_type string) {

    var token string
    var filename string
    var message string

    if strings.Contains(token_type, "top") {
    	token = tokendata.Mytoken_encrypted
        filename = tokendata.Mytoken_file
        message = "Encrypted Mytoken credential"
    } else if strings.Contains(token_type, "use") {
        token = tokendata.Access_token
	filename = tokendata.Access_token_file
        message = "Access token credential"
    } else {
        fmt.Printf("File type not recognized: %s\n", token_type)
	os.Exit(1)
    }

    //-- write credential to tmp file
    tmp_file, _ := ioutil.TempFile(tokendata.Cred_dir_user, token_type + "_*.tmp")
    tmp_file_path := tmp_file.Name()

    if _, err := tmp_file.WriteString(token); err == nil {
        PrintDebug("%s successfully written to tmp file \n\n", message)
        tmp_file.Close()
    } else {
	PrintDebug("Could not write %s to tmp file! \n\n", message)
        tmp_file.Close()
        os.Remove(tmp_file_path)
        Check(err)
    }

    //-- write credential to final destination
    if err := os.Rename(tmp_file_path, filename); err == nil {
       	_ = os.Chmod(filename,0600)
        os.Remove(tmp_file_path)
        PrintDebug("%s successfully written to final destination \n\n", message)
    } else {
        PrintDebug("Could not write %s to final destination! \n\n", message)
        os.Remove(tmp_file_path)
	Check(err)
    }

   //-- revoke mytoken if required
   if strings.Contains(token_type, "top") && tokendata.Mytoken_old != "undefined" {
       Mytoken_revocation_endpoint := tokendata.Mytoken_server.Revocation
       if err := Mytoken_revocation_endpoint.Revoke(tokendata.Mytoken_old, tokendata.Oauth_issuer_url, true); err == nil {
           PrintDebug("Your old credential has been successfully revoked for the issuer %s. \n\n", tokendata.Oauth_issuer_name)
       } else {
           revoke_cmd := exec.Command("mytoken", "revoke", "--MT", tokendata.Mytoken_old)
           if revoke_value, revoke_err := revoke_cmd.CombinedOutput(); revoke_err == nil {
               PrintDebug("Your old credential has been successfully revoked for the issuer %s. \n\n", tokendata.Oauth_issuer_name)
           } else {
               PrintDebug("Your old credential could not be revoked for the issuer %s. \n", tokendata.Oauth_issuer_name)
               PrintDebug("Error first attempt: %v. \n", err)
               PrintDebug("Error second attempt: %v. \n", revoke_err)
               PrintDebug("Output second attempt: %s. \n\n", string(revoke_value))
           }
       }
   }
}

func Lifetime(tokendata *TokenData) {

    info, err := os.Stat(tokendata.Mytoken_file)
    Check(err)

    creation_time := info.ModTime().Unix()
    time_now := time.Now().Unix()
    elapsed_time := time_now - creation_time

    Mytoken_decrypted := Decrypt_mytoken(tokendata)
    Mytoken_trimmed := strings.TrimSpace(string(Mytoken_decrypted))

    claims := jwt.MapClaims{}
    var parser jwt.Parser
    _, _, err_parse := parser.ParseUnverified(string(Mytoken_trimmed), claims)
    Check(err_parse)

    token_lifetime := claims["exp"].(float64) - claims["iat"].(float64)
    token_time := math.Abs(token_lifetime - float64(elapsed_time))

    tokendata.Mytoken_time = float64(token_time)
    mytoken_time_string := fmt.Sprintf("%f", tokendata.Mytoken_time) + "s"
    tokendata.Mytoken_time_dhs, _ = durafmt.ParseString(mytoken_time_string)
}

func Create_access_token(tokendata *TokenData) {

    error_response, access_token_response := Get_access_token_response(tokendata)

    if error_response == nil {
        tokendata.Access_token = access_token_response.AccessToken
        PrintDebug("Access token credential successfully created \n\n")
    }
}

func Get_access_token_response(tokendata *TokenData) (error, api.AccessTokenResponse) {

    var scopes, audiences []string
    var comment string

    Mytoken_decrypted := Decrypt_mytoken(tokendata)
    Mytoken_trimmed := strings.TrimSpace(string(Mytoken_decrypted))

    access_token_endpoint := tokendata.Mytoken_server.AccessToken
    access_token_response, err := access_token_endpoint.APIGet(Mytoken_trimmed, "" , scopes, audiences, comment)

    return err, access_token_response
}

func Renew(tokendata *TokenData, use_case string) bool {

    //-- create or renew if absent
    if _, err := os.Stat(tokendata.Mytoken_file); os.IsNotExist(err) {
	fmt.Printf("No credential has been found! \n\n")
	return true
    }

   Mytoken_decrypted := Decrypt_mytoken(tokendata)
   Mytoken_trimmed := strings.TrimSpace(string(Mytoken_decrypted))
   Mytoken_info_endpoint := tokendata.Mytoken_server.Tokeninfo

   Lifetime(tokendata)

   //-- introspect response is valid
   if _, introspect_error := Mytoken_info_endpoint.Introspect(Mytoken_trimmed); introspect_error == nil {

       fmt.Printf("A valid credential has been found with a remaining life time of %s. \n\n",tokendata.Mytoken_time_dhs)

       //-- offer possibility to renew if "STANDALONE"
       if use_case == "STANDALONE" {

           var user_choice string

           for {
               fmt.Printf("Do you want to renew it? Please answer yes or no: ")
               _,  err := fmt.Scanln(&user_choice)
               Check(err)
	       fmt.Printf("\n")

	       //-- renew
               if user_choice == "yes" {
                   tokendata.Mytoken_old = Mytoken_trimmed
	           return true
	       //-- skip renew
	       } else if user_choice == "no" {
	           return false
               }
           }
       }

   //--	renew if introspect response is not valid
   } else {

       if strings.Contains(introspect_error.Error(), "invalid_token: token is expired") {
           fmt.Printf("Your credential is expired since %s and needs to be renewed! \n\n", tokendata.Mytoken_time_dhs)
       } else {
           fmt.Printf("Your credential has been revoked and needs to be renewed! \n\n")
       }

       PrintDebug("Introspect Error: %s \n\n", introspect_error.Error())
       return true
   }

   //-- skip renew
   return false
}

func Write_email(tokendata *TokenData, email string) {

    filename := tokendata.Email_file

    if email == "undefined" {
         PrintDebug("No email address has been provided. \n\n")
         return
    }

    if _, err := os.Stat(filename); os.IsNotExist(err) {
        file, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY, 0600)
        Check(err)
        defer file.Close()

        if _, err := fmt.Fprintln(file, email); err == nil {
            PrintDebug("The email address %s has been successfully written. \n\n", email)
        } else {
            Check(err)
        }

    } else {
        //-- write email to tmp file
        tmp_file, _ := ioutil.TempFile(tokendata.Cred_dir_user, email + "_*.tmp")
        tmp_file_path := tmp_file.Name()

        _, _ = tmp_file.WriteString(email)
        tmp_file.Close()

       //-- write email to final destination
       _ = os.Rename(tmp_file_path, filename)
       _ = os.Chmod(filename,0600)
       os.Remove(tmp_file_path)
       PrintDebug("The email address %s has been successfully updated. \n\n", email)
    }
}

func Check_existing_email() (bool, string) {

    current_user, _ := user.Current()
    file_email := Parameter("SEC_CREDENTIAL_DIRECTORY_OAUTH") + "/" + current_user.Username + "/email.txt"

    if _, err := os.Stat(file_email); err == nil {
        email, _ := os.ReadFile(file_email)
        return true, strings.TrimSpace(string(email))
    }

    return false, "undefined"

}

func Capitalize(input string) string {

    if len(input) == 0 {
        return input
    }

    input_unicode := []rune(input)
    input_unicode[0] = unicode.ToUpper(input_unicode[0])

    return string(input_unicode)
}

func Convert_Name(input string) string {

    parts := strings.Split(input, ".")

    for i, part := range parts {
        parts[i] = Capitalize(part)
    }

    result := strings.Join(parts, " ")
    return(result)
}