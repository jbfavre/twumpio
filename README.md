# twumpio
=======

Twitter Bridge for pump.io (https://github.com/e14n/pump.io/)

Implements a Ruby daemon to deal with Twitter Rest & Streaming APIs
Uses following Ruby gems (amongst others):

- Twitter for Rest API
- Tweetstream for Streaming API
- MultiJson
- Redis

## Features

- Use Twitter Userstream API to get incoming statuses & events
- Use Twitter Rest API to get missing statuses at restart
- Automatically detect replies, retweets and integrated media (photos)
- Convert statuses into activities
- Convert many Twitter 'events' into activities

## Supported activities

1. 'post' a 'note'/'image'
2. 'share' a 'note'/'image'
3. 'favorite' a 'note'/'image'
4. 'unfavorite' a 'note'/'image'
5. 'follow'/'stop-following' a 'user'
6. 'delete' a 'note'/'image'
