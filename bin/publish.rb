require 'oauth'
require 'oj'
require 'multi_json'

activity = MultiJson.dump({
  id:289296338343038977,
  verb: 'post',
  url:'https://www.twitter.com/statuses/289296338343038977',
  generator:{
    url:'http://pump.io/twumpio/'
  },
  provider:{
    url:'https://www.twitter.com'
  },
  published:'2013-01-10T09:03:16+00:00',
  actor:{
    id:'acct:julien_c@twitter.com',
    url:'https://www.twitter.com/julien_c',
    objectType:'person',
    displayname:'Julien Chaumond',
    image:[
      {
        url:'http://a0.twimg.com/profile_images/2149647940/Julien-Chaumond-crop_normal.jpg',
        height:48,
        width:48
      },
      {
        url:'https://si0.twimg.com/profile_images/2149647940/Julien-Chaumond-crop_normal.jpg',
        height:48,
        width:48
      }
    ]
  },
  object:{
    id:289296338343038977,
    url:'https://www.twitter.com/statuses/289296338343038977',
    objectType:'note',
    content:'13 Design Trends For 2013 - The Industry http://theindustry.cc/2013/01/07/13-design-trends-for-2013/'
  }
})

auth = {
  consumer_key:    "p7fC8e-kTI2DhrJYHbh_OQ",
  consumer_secret: "nSMPTrwErjyCeN8SCn3aIS-60smVTZ7jC2fpLfy9UH0",
  token:           "tSuwc6t8EfVUBe41armLJA",
  token_secret:    "W9fX8lgInYJEFpYGfrzwN1qSMdqfcZDziDuhxKv_xIY"
}

@consumer=OAuth::Consumer.new auth[:consumer_key],
                              auth[:consumer_secret],
                              {
                                :site=>"http://as.jbfav.re:8000"
                              }

@consumer.http.set_debug_output($stderr)

@access_token = OAuth::AccessToken.new(@consumer, auth['token'], auth['token_secret'])

@access_token.post('/api/user/jbfavre/inbox', activity, {"Content-Type"=>"application/json"}).body
#not token provided ???
#@access_token.get('/api/user/jbfavre/inbox').body