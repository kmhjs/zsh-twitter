# zsh-twitter

This project is simple implementation of twitter client in `zsh` .

## Usage

### Source script

source 'path/to/zsh-twitter.sh'

### Prepare consumer information

Before you use this program, you must register your `twitter app` in `twitter develiper site` .  
After that, you must set `Consumer key` and `Consumer secret` as shell environment variable as follows.

```
export TWITTER_CONSUMER_KEY='your consumer key'
export TWITTER_CONSUMER_SECRET='your consumer secret'
```

### Prepare

Authentication is required before you use.

```
twitter_authenticate
```

### Get timeline

When you get home timeline, you can specify number of load items.

```
# Example (10-latest posts from timeline)
twitter_get_home_timeline 10
```

### Post to timeline

```
# Example
twitter_post_timeline_update "I want to eat 🍣"
```

## LICENSE

See `LICENSE` .
