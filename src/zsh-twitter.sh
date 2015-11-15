#! /usr/bin/env zsh

# zsh_twitter_oauth_info_path: -> configuration file path
function zsh_twitter_oauth_info_path() {
    echo "${HOME}/.zsh_twitter_oa_info"
}

# oauth2_url_encode: string -> url encoded string
function oauth2_url_encode() {
    echo -n ${1} | perl -MURI::Escape -lne 'print uri_escape($_)' 
}

# oauth2_generate_oauth_nonce: -> random based 32-character string
function oauth2_generate_oauth_nonce() {
    cat /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | head -c 32
}

# oauth2_generate_oauth_concat_param_str: oauth dict (passed as ${(kv)dict}) -> url parameter like string
function oauth2_generate_oauth_concat_param_str() {
    local -A oauth_dict=($*)

    local concat_param_str=''
    local k
    for k (${(ko)oauth_dict}); do
        concat_param_str+="${k}=$(oauth2_url_encode ${oauth_dict[${k}]})&"
    ; done

    echo -n ${concat_param_str[1,-2]}
}

# oauth2_generate_url_query: oauth dict (passed as ${(kv)dict}) -> url encoded url parameter like string
function oauth2_generate_url_query() {
    local param_str=$(oauth2_generate_oauth_concat_param_str $*)

    oauth2_url_encode ${param_str}
}

# oauth2_generate_authorization_header: oauth dict (passed as ${(kv)dict}) -> authentication header style string
function oauth2_generate_authorization_header() {
    local -A oauth_dict=($*)

    local concat_param_str=''
    local k
    for k (${(ko)oauth_dict}); do
        concat_param_str+="${k}=\"$(oauth2_url_encode ${oauth_dict[${k}]})\", "
    ; done

    echo -n "OAuth ${concat_param_str[1,-3]}"
}

# oauth2_generate_signature: signature base string (coded params), signing_key (consumer secret and oauth secret) -> signature string
function oauth2_generate_signature() {
    local signature_base_string=${1}
    local signing_key=${2}

    echo -n ${signature_base_string} | openssl dgst -sha1 -binary -hmac ${signing_key} | base64
}

# oauth2_generate_base_dict: consumer_key -> dictionary expanded by ${(kv)dict}
function oauth2_generate_base_dict() {
    local consumer_key=${1}
    local -A oauth_dict

    oauth_dict[oauth_nonce]=$(oauth2_generate_oauth_nonce)
    oauth_dict[oauth_signature_method]='HMAC-SHA1'
    oauth_dict[oauth_timestamp]=$(date +%s)
    oauth_dict[oauth_consumer_key]=${consumer_key}
    oauth_dict[oauth_version]='1.0'

    echo ${(kv)oauth_dict}
}

# oauth2_post_request_token: consumer key, consumer secret -> oauth token, (action) open pin code page
function oauth2_post_request_token() {
    local consumer_key=${1}
    local consumer_secret=${2}

    local -A oauth_dict=($(oauth2_generate_base_dict ${consumer_key}))
    local request_api_url='https://api.twitter.com/oauth/request_token'
    local request_api_http_method='POST'

    oauth_dict[oauth_callback]='oob'

    local concat_param_str=$(oauth2_generate_oauth_concat_param_str ${(kv)oauth_dict})

    local signature_base_string=''
    signature_base_string+="${request_api_http_method}&"
    signature_base_string+="$(oauth2_url_encode ${request_api_url})&"
    signature_base_string+="$(oauth2_url_encode ${concat_param_str})"

    local signing_key="$(oauth2_url_encode ${consumer_secret})&"
    oauth_dict[oauth_signature]=$(oauth2_generate_signature "${signature_base_string}" "${signing_key}")

    local oauth_authorization_header=$(oauth2_generate_authorization_header ${(kv)oauth_dict})

    local -A oauth_response=($(curl --silent ${request_api_url} \
                               -X POST -H "Authorization: ${oauth_authorization_header}" | \
                               tr '&=' '  '))

    local result_message=''
    result_message+="oauth_token ${oauth_response[oauth_token]}"
    result_message+=" oauth_token_secret ${oauth_response[oauth_token_secret]}"
    echo ${result_message}

    open "https://api.twitter.com/oauth/authenticate?oauth_token=${oauth_response[oauth_token]}"
}

# oauth2_post_access_token: consumer key, consumer secret, oauth token, oauth token secret, pin code -> oauth token, oauth token secret, screen name, user id (as ${(kv)dict} expanded style)
function oauth2_post_access_token() {
    local consumer_key=${1}
    local consumer_secret=${2}
    local oauth_token=${3}
    local oauth_token_secret=${4}
    local oauth_pin_code=${5}

    local -A oauth_dict=($(oauth2_generate_base_dict ${consumer_key}))
    local request_api_url='https://api.twitter.com/oauth/access_token'
    local request_api_http_method='POST'

    oauth_dict[oauth_token]=${oauth_token}
    oauth_dict[oauth_verifier]=${oauth_pin_code}

    local concat_param_str=$(oauth2_generate_oauth_concat_param_str ${(kv)oauth_dict})

    local signature_base_string=''
    signature_base_string+="${request_api_http_method}&"
    signature_base_string+="$(oauth2_url_encode ${request_api_url})&"
    signature_base_string+="$(oauth2_url_encode ${concat_param_str})"

    local signing_key="$(oauth2_url_encode ${consumer_secret})&$(oauth2_url_encode ${oauth_token_secret})"
    oauth_dict[oauth_signature]=$(oauth2_generate_signature "${signature_base_string}" "${signing_key}")

    local oauth_authorization_header=$(oauth2_generate_authorization_header ${(kv)oauth_dict})

    local -A oauth_response=($(curl --silent ${request_api_url} \
                               -X POST -H "Authorization: ${oauth_authorization_header}" | \
                               tr '&=' '  '))

    local result_message=''
    result_message+="oauth_token ${oauth_response[oauth_token]}"
    result_message+=" oauth_token_secret ${oauth_response[oauth_token_secret]}"
    result_message+=" user_id ${oauth_response[user_id]}"
    result_message+=" screen_name ${oauth_response[screen_name]}"
    echo ${result_message}
}

# oauth2_obtain_oauth_token: consumer key, consumer secret -> (write out) configuration information
function oauth2_obtain_oauth_token() {
    local consumer_key=${1}
    local consumer_secret=${2}

    local -A oauth_info=($(oauth2_post_request_token ${consumer_key} ${consumer_secret}))

    echo -n "Input pin code: "
    read oauth_pin_code
    local -A oauth_verify_info=($(oauth2_post_access_token ${consumer_key} ${consumer_secret} ${oauth_info[oauth_token]} ${oauth_info[oauth_token_secret]} ${oauth_pin_code}))

    : > $(zsh_twitter_oauth_info_path)
    for k v (${(kv)oauth_verify_info}); do
        echo "${k},${v}" >> $(zsh_twitter_oauth_info_path)
    ; done
    echo "consumer_key,${consumer_key}" >> $(zsh_twitter_oauth_info_path)
    echo "consumer_secret,${consumer_secret}" >> $(zsh_twitter_oauth_info_path)
}

# oauth2_get_home_timeline: consumer key, consumer secret, oauth token, oauth token secret, number of items -> (show) home time line
function oauth2_get_home_timeline() {
    local consumer_key=${1}
    local consumer_secret=${2}
    local oauth_token=${3}
    local oauth_token_secret=${4}
    local number_of_items=${5}

    local -A oauth_dict=($(oauth2_generate_base_dict ${consumer_key}))
    local request_api_url='https://api.twitter.com/1.1/statuses/home_timeline.json'
    local request_api_http_method='GET'

    oauth_dict[oauth_token]=${oauth_token}
    oauth_dict[count]=${number_of_items}

    local concat_param_str=$(oauth2_generate_oauth_concat_param_str ${(kv)oauth_dict})

    local signature_base_string=''
    signature_base_string+="${request_api_http_method}&"
    signature_base_string+="$(oauth2_url_encode ${request_api_url})&"
    signature_base_string+="$(oauth2_url_encode ${concat_param_str})"

    local signing_key="$(oauth2_url_encode ${consumer_secret})&$(oauth2_url_encode ${oauth_token_secret})"
    oauth_dict[oauth_signature]=$(oauth2_generate_signature "${signature_base_string}" "${signing_key}")

    local oauth_authorization_header=$(oauth2_generate_authorization_header ${(kv)oauth_dict})

    local result_json=$(echo -e $(curl --silent "${request_api_url}?count=${number_of_items}" \
                                  -X ${request_api_http_method} -H "Authorization: ${oauth_authorization_header}"))

    echo ${result_json}                                  | \
        LC_CTYPE=C tr '{' '\n'                           | \
        egrep '(^"created_at|name)'                      | \
        LC_CTYPE=C tr ',' '\n'                           | \
        egrep '^"(name|text|created_at|screen_name)'     | \
        LC_CTYPE=C sed 's/^"//;s/":"/    ->    /;s/"$//' | \
        LC_CTYPE=C sed 's/^[tns].*$/    | &/g'           | \
        LC_CTYPE=C sed 's/^created_at/$-----$$&/g'       | \
        LC_CTYPE=C tr '$' '\n' | less
}

# oauth2_get_user_timeline: consumer key, consumer secret, oauth token, oauth token secret -> (show) user time line
function oauth2_get_user_timeline() {
    local consumer_key=${1}
    local consumer_secret=${2}
    local oauth_token=${3}
    local oauth_token_secret=${4}

    local -A oauth_dict=($(oauth2_generate_base_dict ${consumer_key}))
    local request_api_url='https://api.twitter.com/1.1/statuses/user_timeline.json'
    local request_api_http_method='GET'

    oauth_dict[oauth_token]=${oauth_token}
    oauth_dict[count]=5

    local concat_param_str=$(oauth2_generate_oauth_concat_param_str ${(kv)oauth_dict})

    local signature_base_string=''
    signature_base_string+="${request_api_http_method}&"
    signature_base_string+="$(oauth2_url_encode ${request_api_url})&"
    signature_base_string+="$(oauth2_url_encode ${concat_param_str})"

    local signing_key="$(oauth2_url_encode ${consumer_secret})&$(oauth2_url_encode ${oauth_token_secret})"
    oauth_dict[oauth_signature]=$(oauth2_generate_signature "${signature_base_string}" "${signing_key}")

    local oauth_authorization_header=$(oauth2_generate_authorization_header ${(kv)oauth_dict})

    local result_json=$(curl --silent "${request_api_url}?count=5" \
                        -X ${request_api_http_method} -H "Authorization: ${oauth_authorization_header}")
    echo ${result_json}
}

# oauth2_get_user_timeline: consumer key, consumer secret, oauth token, oauth token secret, status message ->
function oauth2_post_timeline_update() {
    local consumer_key=${1}
    local consumer_secret=${2}
    local oauth_token=${3}
    local oauth_token_secret=${4}
    local status_string_plain=${5}
    local status_string=$(oauth2_url_encode ${5})

    local -A oauth_dict=($(oauth2_generate_base_dict ${consumer_key}))
    local request_api_url='https://api.twitter.com/1.1/statuses/update.json'
    local request_api_http_method='POST'

    oauth_dict[oauth_token]=${oauth_token}
    oauth_dict[status]=${status_string_plain}

    local concat_param_str=$(oauth2_generate_oauth_concat_param_str ${(kv)oauth_dict})

    local signature_base_string=''
    signature_base_string+="${request_api_http_method}&"
    signature_base_string+="$(oauth2_url_encode ${request_api_url})&"
    signature_base_string+="$(oauth2_url_encode ${concat_param_str})"

    local signing_key="$(oauth2_url_encode ${consumer_secret})&$(oauth2_url_encode ${oauth_token_secret})"
    oauth_dict[oauth_signature]=$(oauth2_generate_signature "${signature_base_string}" "${signing_key}")

    local oauth_authorization_header=$(oauth2_generate_authorization_header ${(kv)oauth_dict})

    local result_json=$(curl --silent "${request_api_url}?status=${status_string}" \
        -X ${request_api_http_method} -H "Authorization: ${oauth_authorization_header}")
}

# twitter_authenticate: -> (write out) configuration
function twitter_authenticate() {
    local consumer_key=${TWITTER_CONSUMER_KEY}
    local consumer_secret=${TWITTER_CONSUMER_SECRET}
    oauth2_obtain_oauth_token ${consumer_key} ${consumer_secret}
}

# twitter_get_home_timeline: (number of items) -> (show) home time line
function twitter_get_home_timeline() {
    local number_of_items

    [[ -z "${1}" ]] && {
        number_of_items=15
    } || {
        number_of_items=${1}
    }

    local -A oauth_info=($(cat $(zsh_twitter_oauth_info_path) | tr ',\n' '  '))
    oauth2_get_home_timeline ${oauth_info[consumer_key]} \
                             ${oauth_info[consumer_secret]} \
                             ${oauth_info[oauth_token]} \
                             ${oauth_info[oauth_token_secret]} \
                             ${number_of_items}
}

# twitter_post_timeline_update: post message ->
function twitter_post_timeline_update() {
    local post_string
    [[ -z "${1}" ]] && return
    post_string=${1}

    local -A oauth_info=($(cat $(zsh_twitter_oauth_info_path) | tr ',\n' '  '))
    oauth2_post_timeline_update ${oauth_info[consumer_key]} \
                                ${oauth_info[consumer_secret]} \
                                ${oauth_info[oauth_token]} \
                                ${oauth_info[oauth_token_secret]} \
                                ${post_string}
}
