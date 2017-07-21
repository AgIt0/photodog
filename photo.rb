require 'cinch'
require 'feedjira'
require 'httparty'
require 'config'

Config.load_and_set_settings(File.join(File.dirname(__FILE__),
                                       'settings.local.yml'))

class PhotoPlugin
  include Cinch::Plugin
  attr_accessor :already_posted

  timer Settings.refresh_period, method: :check_and_post

  def initialize(*args)
    super

    @already_posted = Hash.new { |h, k| h[k] = [] }
  end

  def check_and_post
    Settings.rss_urls.each do |url|
      post_entries_for(url)
    end
  end

  def post_entries_for(url)
    get_entries_for(url).each do |entry|
      already_posted[url] << entry.published
      Channel(Settings.channel).notice(format_entry(entry))
    end
  end

  def format_entry(entry)
    url = entry.url.gsub(/&?\?*utm_.+?(&|$)/, '')
    if url.match('youtube.com')
      "#{entry.author} - #{entry.title} - #{url}"
    else
      "#{entry.title} - #{url}"
    end
  end

  def get_entries_for(url)
    tries = 0

    begin
      xml = HTTParty.get(url).body
      p "Fetching #{url}"
      p "got a #{xml.length} long response"
      feed = Feedjira::Feed.parse(xml)
      entries =
        feed.entries
        .select { |x| x.published > Time.now - Settings.fresh_period * 60 * 60 }
        .reject { |x| already_posted[url].include?(x.published) }
    rescue Feedjira::NoParserAvailable
      p "Refetching for #{url}"
      tries += 1
      if tries > 3
        p "Failed to fetch #{url} :("
        entries = []
      else
        sleep(20)
        retry
      end
    end

    p "Fetched #{url} at #{Time.now} with #{entries.length} entries"
    entries
  end
end

bot = Cinch::Bot.new do
  configure do |c|
    c.user = Settings.user
    c.nick = Settings.nick
    c.server = Settings.server
    c.ssl.use = Settings.use_ssl
    c.port = Settings.port
    c.channels = [Settings.channel]
    c.verbose = true
    c.plugins.plugins = [PhotoPlugin]
  end
end

bot.start
