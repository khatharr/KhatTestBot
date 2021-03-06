# encoding: utf-8
# http://www.rubydoc.info/gems/discordrb/
# http://www.rubydoc.info/gems/similar_text/
require 'net/http'
require 'discordrb'
require 'similar_text'
require 'erb'

$COMMAND_TOKEN = '+'

$BOTBAN_ROLE_NAME = "Dunce"
$MEMBER_ROLE_NAME = "Members"

$INSPIRE_DELAY_SECONDS = 30

$AUTHED_ROOMS = [
  "junk",
  "lounge",
  "gamedev"
]

$pidfile = "/var/run/saatchi.pid"

def say(event, msg)
  okay = false
  
  for role in event.author.roles
    return nil if role.name == $BOTBAN_ROLE_NAME
    if role.name == $MEMBER_ROLE_NAME
      okay = true
      break
    end
  end
  
  if okay
    event.respond(msg) if $chans.include?(event.channel.id)
  end
end

def inspire
  url = "http://inspirobot.me/api?generate=true"
  return Net::HTTP.get(URI(url))
end

def youtube(query)
  return "disabled"
  
  url = "https://www.youtube.com/results?search_query=#{query}"
  
  if Net::HTTP.get(URI(url)) =~ /<a href="(\/watch\?v=.*?)"/
    return "https://www.youtube.com#{$1}"
  end
  
  return nil
end

def wikipedia(query)
  url = "https://en.wikipedia.org/w/api.php?action=query&redirects&format=xml&titles=#{query}"

  data = Net::HTTP.get(URI(url))
  
  idx = -1
  title = ""
  if data =~ /_idx="(\d*?)"/
    idx = $1.to_i
  end
  if data =~ /title="(.*?)"/
    title = $1.gsub(' ', '_')
  end
  
  return "Not found." if idx == -1
  
  return "https://en.wikipedia.org/wiki/#{title}"
end

def loadApps
  puts "Loading DB."
  data = File.read('/home/pi/satchii/applist.txt', :encoding => 'UTF-8')
  lines = data.split("\n")

  $apps = {}
  id = 0
  for line in lines
    if line =~ /appid\"\:\s(.*?)\,/
      id = $1.to_i
    elsif line =~ /\"name\"\:\s\"(.*?)\"/
      $apps[id] = $1
      id = -1
    end
  end
end

def searchApps(query)
  score = 0
  winner = -1
  for k,v in $apps
    short = v.downcase.slice(0, query.length + 4)
    sc = short.similar(query.downcase)
    if sc > score
      score = sc
      winner = k
      break if score == 100
    end
  end
  
  if winner == -1
    return "Not found."
  end
  
  return "http://store.steampowered.com/app/#{winner}"
end

def searchAP(query)
  searchURL = "http://www.anime-planet.com/anime/all?name=#{query}"
  
  resp = Net::HTTP.get_response(URI(searchURL))
  
  if resp.code == '302'
    return "http://www.anime-planet.com" + resp.header['location']
  end
  
  if resp.body =~ /href=\"\/anime\/(.*?)\" class=\"tooltip anime/
    return "http://www.anime-planet.com/anime/#{$1}"
  end
  
  return "Not found."
end

def google(query)
  return "https://www.google.com/search?q=#{query}&ie=utf-8&oe=utf-8"
end

def image(query)
  return "https://www.google.com/search?tbm=isch&q=#{query}"
end

def lmgtfy(query)
  return "<http://lmgtfy.com/?q=#{query}>"
end


def refreshDB(event)
  puts "#{Time.now}: Attempting refresh..."
  say(event, "Refreshing database. Please wait a moment...")
  data = Net::HTTP.get(URI("http://api.steampowered.com/ISteamApps/GetAppList/v2"))
  if data.size == 0
    puts "Refresh failed!"
    say(event, "Refresh failed!")
    return false
  end
  open("/home/pi/satchii/applist.txt", "wb") { |f| f.write(data) }
  puts "Success."
  #say(event, "Success.")
  #say(event, "Reloading DB.")
  loadApps
  return true
end

def loadCredentials
  puts "Loading credentials."
  lines = []
  open("/home/pi/satchii/credentials.dat", "rb") { |f| lines = f.readlines }
  for line in lines
    line.chomp!
  end
  $token = lines[0]
  $appid = lines[1].to_i
  $adminID = lines[2].to_i
end

def startup
  loadCredentials
  loadApps
  
  bot = Discordrb::Commands::CommandBot.new token: $token, application_id: $appid, prefix: $COMMAND_TOKEN
  bot.set_user_permission($adminID, 10)
  
  puts "This bot's invite URL is: \n#{bot.invite_url}"
  puts ("-" * 80) + "\n"
  return bot
end

##########################################

bot = startup

bot.command(:anime, { :description => "Searches Anime Planet for your query (Ex: #{$COMMAND_TOKEN}anime dennou coil)" }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: anime #{args.join(' ')}"
  say(event, searchAP(args.join('+')))
  nil
end

bot.command(:wiki, { :description => "Searches Wikipedia for your query. (Ex: #{$COMMAND_TOKEN}wiki the internet)" }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: wiki #{args.join(' ')}"
  say(event, wikipedia(ERB::Util.url_encode(args.join(' '))))
  nil
end

bot.command(:google, { :description => "Provides a google search link. (Ex: #{$COMMAND_TOKEN}google cat videos)" }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: google #{args.join(' ')}"
  say(event, google(ERB::Util.url_encode(args.join(' '))))
  nil
end

bot.command(:image, { :description => "Provides a google image search link. (Ex: #{$COMMAND_TOKEN}image poop)" }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: image #{args.join(' ')}"
  say(event, image(ERB::Util.url_encode(args.join(' '))))
  nil
end

bot.command(:lmgtfy, { :description => "Google it." }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: lmgtfy #{args.join(' ')}"
  say(event, lmgtfy(ERB::Util.url_encode(args.join(' '))))
  nil
end

bot.command(:steam, { :description => "Searches Steam for a title. (Ex: #{$COMMAND_TOKEN}steam crosscode)" }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: steam #{args.join(' ')}"
  refreshDB(event) if Time.now > (File.mtime("/home/pi/satchii/applist.txt") + (60 * 60 * 12))
  say(event, searchApps(ERB::Util.url_encode(args.join(' '))))
  nil
end

bot.command(:youtube, { :help_available => false, :description => "Return top search result from Youtube. (Ex: #{$COMMAND_TOKEN}youtube dramatic chipmunk)" }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: youtube #{args.join(' ')}"
  say(event, youtube(ERB::Util.url_encode(args.join(' '))))
  nil
end

bot.command(:play, { :help_available => false,  :permission_level => 10 }) do |event, *args|
  puts "#{Time.now} - #{event.author.name}: play #{args.join(' ')}"
  bot.game = args.join(' ')
  nil
end

bot.command(:refresh, { :help_available => false,  :permission_level => 10 }) do |event|
  puts "#{Time.now} - #{event.author.name}: refresh"
  refreshDB(event)
  nil
end

bot.command(:restart, { :help_available => false,  :permission_level => 10 }) do |event|
  puts "#{Time.now} - #{event.author.name}: restart"
  say(event, "Rebooting.")
  bot.stop
  $run = false
  puts "-" * 75
end

bot.command(:twirl,  { :help_available => false,  :permission_level => 10 }) do |event|
  ary = [ "|", "\\", "-" ]
  msg = event.respond("``` ```")
    
  for pos in 0...10
    for c in ary
      sleep(1)
      msg.edit("```" + ("-" * pos) + c + "```")
    end
  end
  sleep(1)
  msg.edit("```-YO-MOMMA-```")
  sleep(1.5)
  msg.delete()
  
  nil
end

bot.command(:del, { :help_available => false,  :permission_level => 10 }) do |event, *args|
  num = args[0].to_i
  if args.empty?
    num = 1
  end
  
  num.times do
    hist = event.channel.history(100)

    for post in hist
      if post.from_bot?
        post.delete()
        break
      end
    end
  end
      
  nil
end

$INSPIRE_TIMER = Time.now


bot.command(:inspire, {:description => "Genreate and post an inspirational poster from InspiroBot.me"}) do |event, *args|
  now = Time.now
  
  if now < $INSPIRE_TIMER + $INSPIRE_DELAY_SECONDS
    event.respond("Please slow down.")
    return nil
  end
  
  event.respond(inspire)
  $INSPIRE_TIMER = now
  nil
end

bot.run_async
bot.game = $COMMAND_TOKEN + "help for commands"
$chans = []
for room in $AUTHED_ROOMS
  $chans += bot.find_channel(room)
end
bot.send_message($chans[0], "Boku Satchii! Yoroshiku ne?") unless $chans.empty?
#sleep(2)
#bot.send_message($chans[0], "TexBot! Yoroshiku!") unless $chans.empty?

$run = true
while $run
  600.times do
    sleep(1)
    break unless $run
  end
  
  bot.game = $COMMAND_TOKEN + "help for commands"
end
