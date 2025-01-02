require_relative 'spec_helper'

describe "Capex Reporting Agent" do
  let(:app) { Sinatra::Application }

  it "renders the index page" do
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('Capex Reporting Agent')
  end

  it "searches for users" do
    post '/search_users', user_search: 'john' 
    expect(last_response).to be_ok
    expect(last_response.body).to include('Search Results')
  end

  it "can add selected users" do
    # Stub the search_users method to return a predefined user ID and display name
    allow_any_instance_of(Sinatra::Application).to receive(:search_users).with('jane') do
      [{ account_id: '123', display_name: 'Jane Smith' }]
    end

    # Stub the fetch_user_display_name method to return the expected name
    allow_any_instance_of(Sinatra::Application).to receive(:fetch_user_display_name).with('123').and_return('Jane Smith')

    visit '/'
    fill_in 'user_search', with: 'jane'
    click_button 'Search'
    first('.add-user-btn').click
    expect(page).to have_content('Jane Smith')
  end
end 