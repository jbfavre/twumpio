require 'twitter'
require 'tweetstream'
require 'json'
require 'multi_json'
require 'redis'
require 'hiredis'
require_relative "../lib/utils"
require_relative "../lib/activitystream"
require_relative "../lib/twumpio"


params = { twitter: { consumer_key:       '',
                      consumer_secret:    '',
                      oauth_token:        '',
                      oauth_token_secret: '' },
           pubsub:  { host: 'localhost', port: 6379, timeout: 0, tcp_keepalive: true } }
Twumpio::Frontend.new(params)
