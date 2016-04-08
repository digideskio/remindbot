require 'json'
require 'github_api'
require 'rest-client'
require 'timezone'
require 'time'

GH             = Github.new(oauth_token: ENV['GH_AUTH_TOKEN'])
OWNER          = ENV['OWNER']
REPO           = ENV['REPO']
SLACK_TOKEN    = ENV['SLACK_TOKEN']
SLACK_BOT_NAME = 'reviewbot'
SLACK_BOT_ICON = ':sleuth_or_spy:'
TIMEZONE       = ENV['TIMEZONE']
REMIND_HOURS   = JSON.parse(ENV['REVIEW_HOURS'])
REVIEWERS      = JSON.parse(ENV['REVIEWERS'])

desc "Send reminders to team members to review PRs"
task :remind do
  exit unless REMIND_HOURS.include?(Timezone[TIMEZONE].utc_to_local(Time.now).hour)

  notifications = GH.pulls.list(OWNER, REPO).body.each_with_object({}) do |pr, by_user|
    print '.'
    labels = GH.issues.get(OWNER, REPO, pr.number).labels.map(&:name)
    next if labels.include?('NOT READY')
    next if labels.include?('+2')

    comments = GH.issues.comments.list(OWNER, REPO, number: pr.number).body.map { |c| { user: c.user.login, comment: c.body } }
    reviewers = comments.select { |c| c[:comment] =~ /^[-\+]1|:[-\+]1:/ }.map { |c| c[:user] }

    candidates = REVIEWERS.keys - [pr.assignee.login] - reviewers

    candidates.each do |candidate|
      by_user[candidate] ||= []
      by_user[candidate] << pr.html_url
    end
  end

  puts

  notifications.each do |user, links|
    next unless (slack_username = REVIEWERS[user])
    RestClient.post(
      'https://slack.com/api/chat.postMessage',
      token: SLACK_TOKEN,
      # channel: "@#{slack_username}",
      channel: "@tim",
      text: "Please review:\n#{links.join("\n")}",
      pretty: 1,
      icon_emoji: SLACK_BOT_ICON,
      username: SLACK_BOT_NAME
    )
    puts "sent #{links.size} to @#{slack_username}"
  end
end