require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'net/http'

CONFIG = YAML.load_file("config.yml")

post '/' do
  push = JSON.parse(params[:payload])
  build_unfuddle_xml_from(push)
end

def build_unfuddle_xml_from(push)
  @repository = push["repository"]
  @commits = push["commits"]
  
  raise "Must specify Unfuddle subdomain, user, and password." unless CONFIG["unfuddle"]["subdomain"] && CONFIG["unfuddle"]["user"] && CONFIG["unfuddle"]["password"]
  raise "Could not map from GitHub project name to Unfuddle Project ID." unless unfuddle_project_id
  
  successes = []
  
  @commits.each do |id, commit|
    timestamp = Time.parse(commit['timestamp'])
    xml = <<-XML
    <changeset>
      #{"<author-id type=\"integer\">#{unfuddle_author_id(commit)}</author-id>" if unfuddle_author_id(commit)}
      <message>#{commit["message"]}
      
Details: #{commit["url"]}</message>
      <revision type="integer">#{timestamp.strftime("%y%m%d%H%M")}</revision>
    </changeset>
    XML
    
    successes << post_changeset_to_unfuddle(xml)
  end
  
  successes.inspect
end

def post_changeset_to_unfuddle(xml)
  http = Net::HTTP.new("#{CONFIG["unfuddle"]["subdomain"]}.unfuddle.com", CONFIG["unfuddle"]["use_ssl"] ? 443 : 80)

  # if using ssl, then set it up
  if CONFIG["unfuddle"]["use_ssl"]
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
  
  begin
    path = "/api/v1/projects/#{unfuddle_project_id}/changesets.xml"
    puts path.inspect
    request = Net::HTTP::Post.new(path, {'Content-type' => 'application/xml'})
    request.basic_auth CONFIG["unfuddle"]["user"], CONFIG["unfuddle"]["password"]
    request.body = xml

    puts request.inspect
    
    response = http.request(request)
    
    if response.code == "201"
      return response['Location']
    else
      puts response.body
      return false
    end
  rescue => e
    puts e.message
    return false
  end
end

def unfuddle_project_id
  CONFIG["repositories"][@repository["name"]]["unfuddle_project_id"]
end

def unfuddle_author_id(commit)
  CONFIG["unfuddle"]["people"][commit["author"]["email"]]
end