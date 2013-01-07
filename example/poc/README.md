# TwumpIO poc

Theses scripts have been (quickly) writtent as a POC.

It requires Ruby 1.9 and uses following Ruby gems:

- Twitter to access Rest API
- Tweetstream to access streaming API
- Redis as backend implementation (tested with Redis 2.6)

## Install
On Debian:

```shell
aptitude install redis-server
gem install twitter tweetstream redis hiredis
```

## Usage
In one terminal, launch:

```shell
ruby redissub.rb
```
It will simulate a pump.io backend and simply displays received JSON ActivityStream.

In another Terminal, launch:

```shell
ruby twumpio.rb
```

It will check on backend for 'tweetin::last_status'.
If found, script will then use Twitter Rest API to catch up missing Tweets
Once catch up, script will automatically switch from Rest API to Streaming API.

Streaming API will then process incoming tweets & events and publish them onto backend.

For now, backend only consists in Redis PubSub channel:

1. Channel is created from twumpio.rb script which push new activities in
2. Channel is subscribed from redissub.rb script, which will display pushed activities.
