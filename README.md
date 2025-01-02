# Capexable Report

## Overview

The Capexable Report application is a web-based tool designed to analyze Jira tickets based on selected assignees and a specified date range. It calculates the capital expenditure (Capex) percentage for each engineer and asset, providing insights into project management and resource allocation.

## Features

- Fetches Jira tickets based on user-defined criteria.
- Calculates an asset group percentage based on story points.
- Supports pagination for retrieving large sets of tickets.
- Allows users to select assignees and specify date ranges.
- Displays results in a user-friendly table format.
- Provides the ability to copy JQL queries to the clipboard.
- Maintains session state for selected users and date ranges.

## Technologies Used

- Ruby
- Sinatra
- HTTParty
- YAML
- JavaScript
- HTML/CSS

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/capexable-report.git
   cd capexable-report
   ```

2. Install the required gems:

   ```bash
   bundle install
   ```

3. Create a `.env` file in the root directory and add your Jira credentials:

   ```plaintext
   JIRA_BASE_URL=https://your-jira-instance.atlassian.net
   JIRA_USERNAME=your-email@example.com
   JIRA_API_KEY=your-api-key
   JIRA_PROJECT_KEY=your-project-key
   ```

4. Start the application:

   ```bash
   ruby app.rb
   ```

5. Open your browser and navigate to `http://localhost:4567`.

## Usage

1. Select the desired users from the list.
2. Specify the default asset and the date range for the analysis.
3. Click the "Analyze" button to fetch and display the results.
4. Review the results table, which includes the engineer name, asset, Capex percentage, supporting JQL, and ticket links.

## Configuration

The application uses a `config.yml` file to define the available assets. You can modify this file to add or remove assets as needed.

## Contributing

Contributions are welcome! If you have suggestions for improvements or new features, please open an issue or submit a pull request.
