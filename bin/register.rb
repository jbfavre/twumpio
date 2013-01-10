require 'oauth'

auth = {}

puts "First, do register a new application on your pump.io instance. For example with curl:"
puts "curl \
  -d 'type=client_associate' \
  -d 'application_type=native' \
  -d 'application_name=twumpio' \
  -d 'application_description=Twitter bridge for pump.io' \
  http://domain.tld:8000/api/client/register"

puts "Given that your instance is hosted at http://domain.tld:8000"
puts "you'll get something like:"
puts "{
  'client_id':'XXXXXXXXXX',
  'client_secret':'XXXXXXXXXXXXXXXXXXXX',
  'expires_at':0
}"
puts "Enter the consumer key (client_id) you have been assigned:"
auth["consumer_key"] = gets.strip
puts "Enter the consumer secret (client_secret) you have been assigned:"
auth["consumer_secret"] = gets.strip
puts "Your application is now set up, but you need to register"
puts "this instance of it with your user account."
 
@consumer=OAuth::Consumer.new auth["consumer_key"],
                              auth["consumer_secret"],
                              {:site=>"http://domain.tld:8000"}

@request_token = @consumer.get_request_token

puts "Visit the following URL, log in if you need to, and authorize the app\n\n"
puts @request_token.authorize_url
puts "\n\nWhen you've authorized that token, enter the verifier code you are assigned:"
verifier = gets.strip
puts "Converting request token into access token...\n\n"
@access_token=@request_token.get_access_token(:oauth_verifier => verifier)

auth["token"] = @access_token.token
auth["token_secret"] = @access_token.secret

puts auth.inspect
