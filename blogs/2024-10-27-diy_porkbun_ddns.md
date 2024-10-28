---
title: Aidan Houck - Blog - DIY Porkbun DDNS
subtitle: It's always DNS until it isn't
date: 2024-10-27
---

# Context
My home ISP gives me a dynamic IPv4 address / IPv6 prefix. This is OK for general internet usage but can get tricky when trying to self-host various services at home. In my case I use my own domain for email, but forward it through Gmail. This means that in order to have a legitimate SPF record I need to tell Google my home IP address is allowed to send emails from `*@aidanhouck.com` addresses. 

## Different solutions
Dynamic DNS is a relatively straightforward tool you can use to automate solving this problem. Typical DNS records will map a domain name to an IP address, such as `one.one.one.one` to `1.1.1.1`:
<pre><samp>
aidan@DESKTOP:~$ dig +noall +answer one.one.one.one
one.one.one.one.        0       IN      A       1.1.1.1
one.one.one.one.        0       IN      A       1.0.0.1
</samp></pre>

The "dynamic" in "Dynamic DNS" is often a script, program, or service that will monitor your IP address (`1.1.1.1`) and automatically update your domain name `one.one.one.one`. There are lots of cool ways to do this, for example:
<ul>
	<li>[ddclient](https://github.com/ddclient/ddclient) is a Perl program that integrates with most DNS providers</li>
	<li>[DuckDNS](https://www.duckdns.org/why.jsp) gives you a subdomain within their domain, meaning you don't need to own your own domain.</li>
	<li>[no-ip](https://www.noip.com/remote-access) does a similar thing but seems to offer more features, in exchange for some money.</li>
	<li>[porkbun-ddns](https://github.com/mietzen/porkbun-ddns) works specifically for my DNS provider, but requires Python which I don't have installed on my system which I'd rather avoid for simplicity's sake.
</ul>

These all seem OK but don't do exactly what I need. With the possible exception of `ddclient` which I did not find out about until halfway through finishing my script... At any rate, why use a working solution when you can spend 5x the time making your own? 

# Putting the DIY in DDNS
Below is the Bash script I created to solve my DDNS problems. It works with [Porkbun](https://porkbun.com/)'s API on a Debian machine. It also pipes output (successful and unsuccessful) to the local mail program which notifies you when your address has changed. You may want to disable this if you have an IP that changes excessively, but mine appears to be only every month or two so I like the extra info.

The first few revisions of this script were heavily inspired by [Jason Burk's blog post](https://grepjason.sh/2022/creating-my-own-dynamic-dns-using-porkbun-api), but over time as I added things like state checking and IPv6 support it grew quite a bit.

## Making API requests
First, define a function that we will use to actually send the requests to Porkbun over [curl](https://curl.se/).
<pre><code>
porkbun_request () {
curl \
--header "Content-type: application/json" \
--data '{"secretapikey":"'"$1"'","apikey":"'"$2"'","content":"'"$3"'"}' \
"$4"
}
</code></pre>

## Define constant variables
Then, we need to define a few constants. These include things like the domain we're using and the subdomain we want to assign our public IP address to. 

This is also where I've defined the file paths to my API key / API secret as well as the URL of the API endpoint. You can find more complete documentation for Porkbun's API [here](https://porkbun.com/api/json/v3/documentation) but this script only really needs to use the one endpoint.
<pre><code>
ddns_domain="ddns"
domain="aidanhouck.com"
domain_fqdn="${ddns_domain}.${domain}"

api_file="/opt/porkbun/.api"
secret_file="/opt/porkbun/.secret"

porkbun_base="https://api.porkbun.com/api/json/v3/dns/editByNameType/${domain}"
</code></pre>

## Fetch current DNS record values
Then I start to actually make requests. This is where I grab the following:
<ol>
	<li>My current IP addresses (`output4`/`output6`)</li>
	<li>The current A/AAAA record values of my WAN FQDN (`test4`/`test6`)</li>
	<li>The current SPF record value compared to expected (`output_spf`/`test_spf`)</li>
</ol>
<pre><code>
output4="$(curl -s https://api.ipify.org | head -c -1)"
test4=$(dig +short ${domain_fqdn} a @1.1.1.1)

output6="$(curl -s https://api64.ipify.org | cut -d':' -f1-4 | head -c -3)00::1"
test6=$(dig +short ${domain_fqdn} aaaa @1.1.1.1)
output6_cidr="$output6/56"

output_spf="v=spf1 include:spf.improvmx.com ip4:$output4 ip6:$output6_cidr ~all"
test_spf=$(dig +short ${domain} txt @1.1.1.1 | tr -d '"')
</code></pre>

## Compare DNS values and make API requests
Finally, we compare each record type (`A`, `AAAA`, `SPF`) to see if the expected and real values match. If they do not we use the function defined earlier to send API requests and return the log/email the results.
<pre><code>
API=$(<"$api_file")
SECRET=$(<"$secret_file")

if ! [ "$output4" = "$test4" ]; then
	echo "`date +"%b %d %H:%M%:S"` Attempting to update IPv4 DDNS from `hostname`"
        result=$(porkbun_request "$SECRET" "$API" "$output4" "${porkbun_base}/A/${ddns_domain}")
        printf "%s\n\n%s\n%s\n" "Tried changing ${test4} to ${output4}" "Result:" "$result" | tee /dev/stderr | /usr/bin/mail -s "`hostname` updated IPv4 DDNS" `hostname`@aidanhouck.com
fi

if ! [ "$output6" = "$test6" ]; then
	echo "`date +"%b %d %H:%M%:S"` Attempting to update IPv6 DDNS from `hostname`"
        result $(porkbun_request "$SECRET" "$API" "$output6" "${porkbun_base}/AAAA/${ddns_domain}")
        printf "%s\n\n%s\n%s\n" "Tried changing ${test6} to ${output6}" "Result:" "$result" | tee /dev/stderr | /usr/bin/mail -s "`hostname` updated IPv6 DDNS" `hostname`@aidanhouck.com
fi

if ! [ "$output_spf" = "$test_spf" ]; then
	echo "`date +"%b %d %H:%M%:S"` Attempting to update SPF DDNS from `hostname`"
        result=$(porkbun_request "$SECRET" "$API" "$output_spf" "${porkbun_base}/TXT")
        printf "%s\n\n%s\n%s\n" "Tried changing ${test_spf} to ${output_spf}" "Result:" "$result" | tee /dev/stderr | /usr/bin/mail -s "`hostname` updated SPF DDNS" `hostname`@aidanhouck.com
fi
</code></pre>

# Automating things with a Cronjob
I have two DNS containers both running [Pi-hole](https://pi-hole.net/) and [Unbound](https://www.unbound.org/), so the script is added to a recurring [Cronjob](https://en.wikipedia.org/wiki/Cron) on both hosts. In `crontab -e` I have the following lines added:
<pre><code>
# ON NS1
00 1,13 * * * "/opt/porkbun/ddns-update.sh" 2>&1 >> /var/log/syslog

# ON NS2
15 1,13 * * * "/opt/porkbun/ddns-update.sh" 2>&1 >> /var/log/syslog
</code></pre>

This means that <abbr title="Name Server 1">NS1</abbr> will always [run at 0100/1300](https://crontab.guru/#00_1,13_*_*_*), while <abbr title="Name Server 2">NS2</abbr> will [run at 0115/1315](https://crontab.guru/#15_1,13_*_*_*). The primary DNS server will handle any legitimate updates 99% of the time, while the secondary is available to do updates if NS1 does not catch them for whatever reason. 

# Full Script
If you'd like the full script for ease of copy-paste you can find it in the spoiler below. Have a good day.
<details>
	<summary>ddns-update.sh</summary>
	<pre><code>
#!/bin/bash

# A script to dynamically update porkbun DNS values with changing public IP address

# USAGE: porkbun_request SECRET API IP URL/TYPE/SUB
porkbun_request () {
curl \
--header "Content-type: application/json" \
--data '{"secretapikey":"'"$1"'","apikey":"'"$2"'","content":"'"$3"'"}' \
"$4"
}

# Declare vars
ddns_domain="ddns"
domain="aidanhouck.com"
domain_fqdn="${ddns_domain}.${domain}"

api_file="/opt/porkbun/.api"
secret_file="/opt/porkbun/.secret"

porkbun_base="https://api.porkbun.com/api/json/v3/dns/editByNameType/${domain}"

# Grab data
output4="$(curl -s https://api.ipify.org | head -c -1)"
test4=$(dig +short ${domain_fqdn} a @1.1.1.1)

output6="$(curl -s https://api64.ipify.org | cut -d':' -f1-4 | head -c -3)00::1"
test6=$(dig +short ${domain_fqdn} aaaa @1.1.1.1)
output6_cidr="$output6/56"

output_spf="v=spf1 include:spf.improvmx.com ip4:$output4 ip6:$output6_cidr ~all"
test_spf=$(dig +short ${domain} txt @1.1.1.1 | tr -d '"')

# Make sure requests complete
sleep 2s

# Read API keys from file
API=$(<"$api_file")
SECRET=$(<"$secret_file")

# Make requests if resource needs updated
if ! [ "$output4" = "$test4" ]; then
	echo "`date +"%b %d %H:%M%:S"` Attempting to update IPv4 DDNS from `hostname`"
        result=$(porkbun_request "$SECRET" "$API" "$output4" "${porkbun_base}/A/${ddns_domain}")
        printf "%s\n\n%s\n%s\n" "Tried changing ${test4} to ${output4}" "Result:" "$result" | tee /dev/stderr | /usr/bin/mail -s "`hostname` updated IPv4 DDNS" `hostname`@aidanhouck.com
fi

if ! [ "$output6" = "$test6" ]; then
	echo "`date +"%b %d %H:%M%:S"` Attempting to update IPv6 DDNS from `hostname`"
        result $(porkbun_request "$SECRET" "$API" "$output6" "${porkbun_base}/AAAA/${ddns_domain}")
        printf "%s\n\n%s\n%s\n" "Tried changing ${test6} to ${output6}" "Result:" "$result" | tee /dev/stderr | /usr/bin/mail -s "`hostname` updated IPv6 DDNS" `hostname`@aidanhouck.com
fi

if ! [ "$output_spf" = "$test_spf" ]; then
	echo "`date +"%b %d %H:%M%:S"` Attempting to update SPF DDNS from `hostname`"
        result=$(porkbun_request "$SECRET" "$API" "$output_spf" "${porkbun_base}/TXT")
        printf "%s\n\n%s\n%s\n" "Tried changing ${test_spf} to ${output_spf}" "Result:" "$result" | tee /dev/stderr | /usr/bin/mail -s "`hostname` updated SPF DDNS" `hostname`@aidanhouck.com
fi
	</code></pre>
</details>