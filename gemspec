spec = Gem::Specification.new do |s|
  s.name = 'rlogin'
  s.rubyforge_project = 'rlogin'
  s.version = '1.0.1'
  s.summary = "Net::Rlogin package to connect with rlogind servers"
  s.description = %{Ruby library to connect to a BSD Rlogin server (RFC 1282).}
  s.files = Dir['lib/**/*.rb'] + Dir['test/**/*.rb']
  s.require_path = 'lib'
  s.has_rdoc = true
  s.extra_rdoc_files = ["licence.txt"]
  s.author = "Vincent Landgraf"
  s.email = "vilandgr+rlogin@googlemail.com"
  s.homepage = "http://rlogin.rubyforge.org"
end

