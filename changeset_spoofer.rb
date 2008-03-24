require 'net/http'
require 'yaml'

puts YAML.load_file("config.yml").inspect

puts "Enter data to be sent to the bridge:"
input = gets.chomp!

res = Net::HTTP.post_form(URI.parse('http://localhost:4567/'), {"payload" => input})

puts(res.body)