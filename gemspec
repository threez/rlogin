spec = Gem::Specification.new do |s|
  s.name = 'rlogin'
  s.rubyforge_project = 'rlogin'
  s.version = '1.0.0'
  s.summary = "Net::Rlogin package to connect with rlogind servers"
  s.description = %{Simple builder classes for creating markup.}
  s.files = Dir['lib/**/*.rb'] + Dir['test/**/*.rb']
  s.require_path = 'lib'
  s.has_rdoc = true
  s.extra_rdoc_files = ["licence.txt"]
  s.author = "Vincent Landgraf"
  s.email = "vilandgr+rlogin@googlemail.com"
  s.homepage = "http://rlogin.rubyforge.org"
end

