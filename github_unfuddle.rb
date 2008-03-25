require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'net/http'
require 'tinder'
require 'erb'

CONFIG = YAML.load_file("config.yml")
REPOS = YAML.load_file("repos.yml")

class GithubCampfire
  
  def initialize(payload)
    payload = JSON.parse(payload)
    return unless payload.keys.include?("repository")
    @repo = payload["repository"]["name"]
    @template = ERB.new(REPOS[@repo]["template"] || "[<%= commit['repo'] %>] <%= commit['message'] %> - <%= commit['author']['name'] %> (<%= commit['url'] %>)")
    @room = connect(@repo)
    payload["commits"].each { |c| process_commit(c.last) }
  end
  
  def connect(repo)
    credentials = REPOS[repo]
    campfire = Tinder::Campfire.new(credentials['subdomain'])
    campfire.login(credentials['username'], credentials['password'])
    return campfire.find_room_by_name(credentials['room'])
  end
  
  def process_commit(commit)
    #we don't need all sorts of local_assigns eval shit here, so this'll do
    commit["repo"] = @repo
    proc = Proc.new do 
      commit
    end
    @room.speak(@template.result(proc))
  end
  
end


post '/' do
  push = JSON.parse(params[:payload])
  GithubCampfire.new(params[:payload])
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
      <revision type="integer">#{timestamp.strftime("%y%m%d%H%M")}</revision>
Details: #{commit["url"]}</message>
    </changeset>
    XML
    
    successes << post_changeset_to_unfuddle(xml)
  end
  
  successes
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
    
    request = Net::HTTP::Post.new(path, {'Content-type' => 'application/xml'})
    request.basic_auth CONFIG["unfuddle"]["user"], CONFIG["unfuddle"]["password"]
    request.body = xml

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