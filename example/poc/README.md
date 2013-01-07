# TwumpIO poc

Theses scripts have been (quickly) writtent as a POC.
It requires Ruby 1.9
It uses following Ruby gems:

- Twitter to access Rest API
- Tweetstream to access streaming API
- Redis as backend implementation (tested with Redis 2.6)

## Install
On Debian:
aptitude install redis-server
gem install twitter tweetstream redis hiredis

## Usage
In one terminal, launch:
ruby redissub.rb

It will simulate a pump.io backend. It's simply display received JSON ActivityStream.

In another Terminal, launch:
ruby twumpio.rb

It will check on backend for 'tweetin::last_status'.
If found, script will then use Twitter Rest API to catch up missing Tweets
Once catch up, script will automatically switch from Rest API to Streaming API.
Streaming API will process incoming tweets & events and publish them onto backend.

For now, backend only consists in Redis PubSub channel.
Channel is created from twumpio.rb script which push new activities in, and
subscribed from redissub.rb script, which will display pushed activities.
