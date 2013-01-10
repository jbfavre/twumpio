require 'oauth'
require 'oj'
require 'multi_json'

activity = MultiJson.dump("{'id':289296338343038977,'verb':'post','url':'https://www.twitter.com/statuses/289296338343038977','generator':{'url':'http://pump.io/twumpio/''},'provider':{'url':'https://www.twitter.com'},'published':'2013-01-10T09:03:16+00:00','actor':{'id':'acct:julien_c@twitter.com','url':'https://www.twitter.com/julien_c','objecttype':'person','displayname':'Julien Chaumond','image':[{'url':'http://a0.twimg.com/profile_images/2149647940/Julien-Chaumond-crop_normal.jpg','height':48,'width':48},{'url':'https://si0.twimg.com/profile_images/2149647940/Julien-Chaumond-crop_normal.jpg','height':48,'width':48}]},'object':{'id':289296338343038977,'url':'https://www.twitter.com/statuses/289296338343038977','objecttype':'note','content':'13 Design Trends For 2013 - The Industry http://theindustry.cc/2013/01/07/13-design-trends-for-2013/'}}")

auth = {
  consumer_key:       'pDMwGtYBZUt8-6VvhvP4Yw',
  consumer_secret:    '6kSGYK0OtIAs5mtxOmldiRPW9iGDJ3CBwZkIQHr2d10',
  oauth_token:        'U4SYDz9jBrrh6c4yM_15ig',
  oauth_token_secret: '1x4WborKleb8H69ZtA87XbfTvIDffzm0bl-O23gZdzw'
}

@consumer=OAuth::Consumer.new auth[:consumer_key],
                              auth[:consumer_secret],
                              {
                                :site=>"http://as.jbfav.re:8000",
                              }

@access_token = OAuth::AccessToken.new(@consumer, auth['token'], auth['token_secret'])

puts "\n\n=================================================="
p @access_token.post('/api/user/jbfavre/inbox/major', activity, {"Content-Type"=>"application/json"}).body
#p @access_token.get('/api/user/jbfavre/inbox').body
puts "\n\n=================================================="
