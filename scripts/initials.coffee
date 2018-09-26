# Description:
#   Gets the initials of brothers in PKT
#
# Commands:
#   hubot initials add <initials> <year> <slack ping> - Adds person to initials database
#   hubot initials get <initials> - Returns the person with the given initials.
#   hubot initials get <username> - Returns the person wtih the given slack username.
#
# Author:
#   Detry322

sendUser = (robot, res, user) ->
  res.send "*#{user['initials']}*: #{user['real_name']}, PKT '#{user['year']}, Slack: #{robot.pingStringForUser(user)}, Email: #{user['email_address']}"

module.exports = (robot) ->

  robot.brain.userForInitials = (initials) ->
    for own key, user of robot.brain.data.users
      if user['initials'] == initials
        return user
    return null

  robot.respond /initials add ([A-Z]{3}) ([0-9]{2}) @?([a-z0-9_\-\.]+)$/, (res) ->
    initials = res.match[1].toUpperCase()
    year = parseInt(res.match[2])
    slack_name = res.match[3]
    name = slack_name
    user = robot.brain.userForName(slack_name)
    if user?
      user['initials'] = initials
      user['year'] = year
      sendUser(robot, res, user)
      name = user['real_name']
    initials_table = robot.brain.get('pkt-initials') or {}
    initials_table[initials] = {
      initials: initials,
      year: year,
      name: name
    }
    robot.brain.set('pkt-initials', initials_table)
    res.send "Added *#{initials}*: #{name}, PKT '#{year}"

  robot.respond /initials get ([A-Z]{3})$/, (res) ->
    initials = res.match[1].toUpperCase()
    user = robot.brain.userForInitials(initials)
    if user?
      sendUser(robot, res, user)
    else
      # This means they were never matched with a slack user => alum?
      initials_table = robot.brain.get('pkt-initials') or {}
      if initials_table[initials]?
        person = initials_table[initials]
        res.send "*#{person['initials']}*: #{person['name']}, PKT '#{person['year']}"
      else
        res.send "No one with initials #{initials} exists."

  robot.respond /initials get @?([a-z0-9_\-]+)$/, (res) ->
    slack_name = res.match[1]
    user = robot.brain.userForName(slack_name)
    if user? and user['initials']
      sendUser(robot, res, user)
    else
      res.send "No one with username #{slack_name} exists."
