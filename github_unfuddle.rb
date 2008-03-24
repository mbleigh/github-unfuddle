require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'

post '/' do
  puts "\n\n#{params[:payload]}\n\n"
  push = JSON.parse(params[:payload])
  build_unfuddle_xml_from(push)
end

def build_unfuddle_xml_from(push)
  puts push.inspect
  config = YAML.load_file("config.yml")  
  repository = push["repository"]
  commits = push["commits"]
  output = ""
  
  commits.each do |id, commit|
    timestamp = Time.parse(commit['timestamp'])
    xml = <<-XML
    <changeset>
      #{"<author-id type=\"integer\">#{config["unfuddle"]["people"][commit["author"]["email"]]}</author-id>" if config["unfuddle"]["people"][commit["author"]["email"]]}
      <message>#{commit["message"]}
      
[More Detail](#{commit["url"]})</message>
      <revision type="integer">#{timestamp.strftime("%y%m%d%H%M")}</revision>
    </changeset>
    XML
    
    output << xml
  end
  output
end