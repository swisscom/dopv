#
# DOPv CLI
#

require 'dopv'
require 'thor'

class Dopv::Cli < Thor
	desc "hello NAME", "say hello to NAME"
	def hello(name)
		puts "Hello #{name}"
	end
end
