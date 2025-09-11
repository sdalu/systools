Gem::Specification.new do |s|
  s.name        = "systools"
  s.version     = "0.1.0"
  s.summary     = "System tools."
  s.description = "A set of system tools."
  s.authors     = [ "Stéphane D'Alu" ]
  s.email       = [ "sdalu@sdalu.com" ]

  s.files = Dir["lib/**/*.rb"]
  s.require_paths = ["lib"]

  s.executables = [ 'zfs-snapshot' ]
  
  # Specify your dependencies here
  s.add_dependency 'pastel'
  s.add_dependency 'tty-logger'
  s.add_dependency 'tty-spinner'
  s.add_dependency 'tty-progressbar'
end
