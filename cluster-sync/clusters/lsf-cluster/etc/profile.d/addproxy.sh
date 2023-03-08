# set proxy config via profile.d - should apply for all users

PROXY_URL="//10.3.0.3:3128"
export http_proxy="http:$PROXY_URL"
export https_proxy="http:$PROXY_URL"
export ftp_proxy="http:$PROXY_URL"
export no_proxy="127.0.0.1,localhost,.sls30lab.com,10.3.196.40,10.3.196.41"

export HTTP_PROXY="http:$PROXY_URL"
export HTTPS_PROXY="http:$PROXY_URL"
export FTP_PROXY="http:$PROXY_URL"
export NO_PROXY="127.0.0.1,localhost,.sls30lab.com,10.3.196.40,10.3.196.41"

