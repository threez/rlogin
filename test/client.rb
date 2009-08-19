require "../lib/rlogin"

username, host = ARGV.shift.split("@")
password = ARGV.shift

Net::Rlogin.new(host, username, :password => password) do |session|
  print "##### $> "
  begin
    cmd = STDIN.gets.chomp
    if cmd =~ /exit/
      session.logout
    else
      print session.cmd(cmd, false, true)
    end
  end while session.logged_in?
end

