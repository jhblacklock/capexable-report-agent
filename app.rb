# app.rb
require 'sinatra'
require 'yaml'
require 'httparty'
require 'json'
require 'dotenv/load'
require 'date'  # Ensure the Date class is available

# Add the end_of_quarter method to the Date class
class Date
  def end_of_quarter
    month = self.month
    quarter_end_month = ((month - 1) / 3 + 1) * 3
    Date.new(self.year, quarter_end_month, -1) # Last day of the month
  end
end

# Load assets from config.yml
assets = YAML.load_file('config.yml')['assets']
default_asset = YAML.load_file('config.yml')['default_asset']

helpers do
  def selected_assignees
    session[:selected_assignees]&.map { |assignee| assignee.transform_keys(&:to_sym) } || []
  end
end

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(64)
  set :jira_base_url, ENV['JIRA_BASE_URL']
  set :jira_api_key, ENV['JIRA_API_KEY']
  set :jira_project_key, ENV['JIRA_PROJECT_KEY']
  set :jira_username, ENV['JIRA_USERNAME']
end

# Set default from_date and to_date for the current quarter in a route
before do
  if session[:from_date].nil? || session[:to_date].nil?
    current_time = Time.now
    current_quarter = (current_time.month - 1) / 3 + 1
    year = current_time.year

    # Calculate the start and end dates of the current quarter
    from_date = Date.new(year, (current_quarter - 1) * 3 + 1, 1)
    to_date = from_date.end_of_quarter

    session[:from_date] ||= from_date.strftime('%Y-%m-%d')
    session[:to_date] ||= to_date.strftime('%Y-%m-%d')
  end
end

get '/' do
  erb :index, locals: { assignees: [], selected_assignees: selected_assignees, assets: assets, default_asset: default_asset, from_date: session[:from_date], to_date: session[:to_date] }
end

post '/search_users' do
  user_search = params[:user_search]
  assignees = search_users(user_search)
  newly_selected_assignee_ids = params[:assignees] || []

  newly_selected_assignees = newly_selected_assignee_ids.map do |id|
    { account_id: id, display_name: fetch_user_display_name(id) }
  end

  session[:selected_assignees] = (selected_assignees + newly_selected_assignees).uniq.map { |assignee| assignee.transform_keys(&:to_sym) }

  erb :index, locals: { assignees: assignees, selected_assignees: selected_assignees, assets: assets, default_asset: default_asset, from_date: session[:from_date], to_date: session[:to_date] }
end

post '/analyze' do
  # Use session variables for from_date and to_date
  from_date = params[:from_date]
  to_date = params[:to_date]
  assignees = params[:assignees] || []
  default_asset = params[:default_asset]

  session[:from_date] = from_date
  session[:to_date] = to_date
  assignees = params[:assignees] || []
  default_asset = params[:default_asset]
  session[:selected_assignees] = assignees.map do |id|
    { account_id: id, display_name: fetch_user_display_name(id) }
  end

  # Fetch tickets from Jira API based on selected assignees and date range
  tickets = fetch_tickets(from_date, to_date, assignees)

  if tickets.nil?
    # If no tickets found, render results with empty array
    erb :results, locals: { results: [] }
  else
    # Categorize and group tickets by engineer and asset
    grouped_tickets = group_tickets(tickets, assets, default_asset)

    # Calculate Capex % for each engineer and asset
    results = calculate_capex_percentage(grouped_tickets, from_date, to_date)

    # Render the results
    erb :results, locals: { results: results, from_date: from_date, to_date: to_date }
  end
end

def fetch_tickets(from_date, to_date, assignees)
  # Parse and format the date values
  formatted_from_date = Date.parse(from_date).strftime('%Y-%m-%d')
  formatted_to_date = Date.parse(to_date).strftime('%Y-%m-%d')

  # Generate JQL query based on date range and assignee IDs
  jql = generate_jql(from_date, to_date, assignees)

  all_issues = []
  start_at = 0
  max_results = 50 # Adjust this value based on your needs

  loop do
    # Make API request to fetch tickets
    response = HTTParty.get("#{settings.jira_base_url}/rest/api/3/search",
      query: { jql: jql, startAt: start_at, maxResults: max_results }, 
      basic_auth: {
        username: settings.jira_username,
        password: settings.jira_api_key
      },
      headers: { 'Accept' => 'application/json' }
    )
    
    if response.success?
      result = JSON.parse(response.body)
      all_issues.concat(result['issues'])
      break if result['issues'].size < max_results
    else
      puts "Error fetching tickets: #{response.code} - #{response.body}"
      break
    end

    start_at += max_results
  end

  all_issues
end

def generate_jql(from_date, to_date, assignees)
  formatted_assignees = Array(assignees).map { |id| "'#{id}'" }.join(',')
  formatted_from_date = Date.parse(from_date).strftime('%Y-%m-%d')
  formatted_to_date = Date.parse(to_date).strftime('%Y-%m-%d')

  date_conditions = [
    "updated >= '#{formatted_from_date}' AND updated <= '#{formatted_to_date}'",
    "'Start date' >= '#{formatted_from_date}' AND 'Start date' <= '#{formatted_to_date}'",
    "resolutiondate >= '#{formatted_from_date}' AND resolutiondate <= '#{formatted_to_date}'",
    "resolved >= '#{formatted_from_date}' AND resolved <= '#{formatted_to_date}'"
  ].join(' OR ')

  assignee_conditions = "assignee IN (#{formatted_assignees})"

  "(#{date_conditions}) AND created > -365d AND (#{assignee_conditions}) AND project = #{settings.jira_project_key} ORDER BY updated ASC"
end

def group_tickets(tickets, assets, default_asset)
  grouped_tickets = {}

  tickets.each do |ticket|
    assignee = ticket['fields']['assignee']['displayName'] 
    asset = map_asset(ticket, assets, default_asset)

    grouped_tickets[assignee] ||= {}
    grouped_tickets[assignee][asset] ||= {
      capexable_points: 0,
      non_capexable_points: 0,
      total_points: 0,
      tickets: []
    }

    story_points = ticket['fields']['customfield_10036'] || 1
    is_capexable = !ticket['fields']['issuetype']['name'].downcase.include?('bug')

    if is_capexable
      grouped_tickets[assignee][asset][:capexable_points] += story_points
    else
      grouped_tickets[assignee][asset][:non_capexable_points] += story_points  
    end

    grouped_tickets[assignee][asset][:total_points] += story_points
    grouped_tickets[assignee][asset][:tickets] << ticket
  end

  grouped_tickets
end

def map_asset(ticket, assets, default_asset)
  title = ticket['fields']['summary'].to_s.downcase
  description = ticket['fields']['description'].to_s.downcase

  # Improved matching logic using regex for partial matches
  asset = assets.find { |a| title.match?(/#{Regexp.escape(a.downcase)}/) || description.match?(/#{Regexp.escape(a.downcase)}/) }
  asset || default_asset
end

def calculate_capex_percentage(grouped_tickets, from_date, to_date)
  results = []

  grouped_tickets.each do |assignee, assets|
    total_capexable_points = assets.values.sum { |data| data[:capexable_points] }
    total_points = assets.values.sum { |data| data[:total_points] }

    next if total_points.zero?  # Skip if total points are zero to avoid division by zero

    assignee_capex_percentage = (total_capexable_points.to_f / total_points * 100).round(2)

    assets.each do |asset, data|
      next if total_capexable_points.zero?  # Skip if capexable points are zero

      asset_capex_percentage = (data[:capexable_points].to_f / total_capexable_points * assignee_capex_percentage).round(2)

      # Collect ticket information for the asset
      ticket_links = data[:tickets].map do |ticket|
        ticket_id = ticket['key']  # Assuming 'key' contains the ticket ID like LO-XXXX
        is_bug = ticket['fields']['issuetype']['name'].downcase.include?('bug')  # Check if the ticket is a bug
        link_color = is_bug ? 'red' : 'blue'  # Set color based on whether it's a bug
        "<a href='#{settings.jira_base_url}/browse/#{ticket_id}' style='color: #{link_color};'>#{ticket_id}</a>"
      end.join(', ')

      results << {
        engineer: assignee,
        asset: asset,
        capex_percentage: "#{asset_capex_percentage}%",
        jql: generate_jql(from_date, to_date, assignee),
        ticket_links: ticket_links  # Add ticket links to the result
      } if asset_capex_percentage > 0  # Only include if asset capex percentage is greater than 0
    end
  end

  results
end

def fetch_assignees
  # Make API request to fetch users
  response = HTTParty.get("https://truecar.atlassian.net/rest/api/3/user/search/query",
    query: {
      query: "is assignee of (#{settings.jira_project_key}) AND active = true"
    },
    basic_auth: {
      username: settings.jira_username,
      password: settings.jira_api_key
    },
    headers: { 'Accept' => 'application/json' }
  )

  JSON.parse(response.body).map { |user| { account_id: user['accountId'], display_name: user['displayName'] } }
end

def search_users(query)
  response = HTTParty.get("#{settings.jira_base_url}/rest/api/3/user/search",
    query: { query: query },
    basic_auth: {
      username: settings.jira_username,
      password: settings.jira_api_key
    },
    headers: { 'Accept' => 'application/json' }
  )

  JSON.parse(response.body).map { |user| { account_id: user['accountId'], display_name: user['displayName'] } }
end

post '/add_user' do
  request.body.rewind
  data = JSON.parse(request.body.read)
  user_to_add = data['add_user'].transform_keys(&:to_sym)
  selected_assignees = session[:selected_assignees] || []
  
  if selected_assignees.any? { |assignee| assignee[:account_id] == user_to_add[:account_id] }
    status 409 # User already exists, return conflict status
  else
    session[:selected_assignees] = selected_assignees << user_to_add
    status 200 # User added successfully
  end
  
  p "session[:selected_assignees]: #{session[:selected_assignees]}"
end

def fetch_user_display_name(account_id)
  response = HTTParty.get("#{settings.jira_base_url}/rest/api/3/user?accountId=#{account_id}",
    basic_auth: {
      username: settings.jira_username,
      password: settings.jira_api_key
    },
    headers: { 'Accept' => 'application/json' }
  )

  JSON.parse(response.body)['displayName']
end

post '/remove_user' do
  request.body.rewind
  data = JSON.parse(request.body.read)
  account_id = data['account_id']
  session[:selected_assignees] = selected_assignees.reject { |assignee| assignee[:account_id] == account_id }
  status 200
end

# Add routes to set from_date and to_date
post '/set_dates' do
  session[:from_date] = params[:from_date] if params[:from_date]
  session[:to_date] = params[:to_date] if params[:to_date]
  status 200
end
