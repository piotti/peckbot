# Description:
#   Hubot interface for the PKT Laundry Calendar
#
# Commands:
#   hubot laundry - gets next 10 laundry appointments
#   hubot laundry add <date> - makes you a laundry appointment for <date>
#   hubot laundry remove <id> - deletes the laundry appointment with id
#   hubot laundry next - returns your next appointment.
#
# Author:
#   Detry322

fs = require('fs')
readline = require('readline')
google = require('googleapis')
googleAuth = require('google-auth-library')
chrono = require('chrono-node')
moment = require('moment')

SCOPES = ['https://www.googleapis.com/auth/calendar']

credentials_json = null;

authorize = (robot, res, callback) ->
  if credentials_json?
    callback(credentials_json)
    return
  fs.readFile 'client_secret.json', (err, content) ->
    if err?
      res.send "Error loading client_secret.json file"
      return
    credentials_json = JSON.parse(content)
    callback(credentials_json)

getClient = (robot, res, callback) ->
  authorize robot, res, (credentials) ->
    clientSecret = credentials.installed.client_secret;
    clientId = credentials.installed.client_id;
    redirectUrl = credentials.installed.redirect_uris[0];
    auth = new googleAuth();
    oauth2Client = new auth.OAuth2(clientId, clientSecret, redirectUrl);
    callback(oauth2Client);

getAuthedClient = (robot, res, callback) ->
  getClient robot, res, (oauth2Client) ->
    token = robot.brain.get 'laundry-calendar-token'
    if token?
      oauth2Client.credentials = token
      callback(oauth2Client)
      return
    authUrl = oauth2Client.generateAuthUrl {
      access_type: 'offline',
      scope: SCOPES
    }
    res.send "This app is not yet authorized, please visit this URL (when logged into the pktlaundry@gmail.com account):\n" + authUrl
    res.send "Enter that code by sending 'peckbot laundry storetoken <token>'"

storeToken = (robot, res, code, callback) ->
  getClient robot, res, (oauth2Client) ->
    oauth2Client.getToken code, (err, token) ->
      if err?
        res.send "Error while trying to retrieve access token"
        return
      robot.brain.set 'laundry-calendar-token', token
      oauth2Client.credentials = token
      callback(oauth2Client)

apiWrapper = (res, callback) ->
  return (err, response) ->
    if err?
      res.send 'The API returned an error: ' + err
      return
    callback(response);

getAllAppointments = (robot, res, num, callback) ->
  getAuthedClient robot, res, (oauth2Client) ->
    google.calendar('v3').events.list {
      auth: oauth2Client,
      calendarId: 'primary',
      timeMin: (new Date()).toISOString(),
      maxResults: num,
      singleEvents: true,
      orderBy: 'startTime'
    }, apiWrapper res, (response) ->
      callback(null, response.items)

getNextAppointment = (robot, res, user, callback) ->
  getAuthedClient robot, res, (oauth2Client) ->
    google.calendar('v3').events.list {
      auth: oauth2Client,
      calendarId: 'primary',
      timeMin: (new Date()).toISOString(),
      maxResults: 1,
      singleEvents: true,
      q: user,
      orderBy: 'startTime'
    }, apiWrapper res, (response) ->
      if response.items.length == 0
        callback(true)
        return
      callback(null, response.items[0])

createAppointment = (robot, res, user, date, callback) ->
  getAuthedClient robot, res, (oauth2Client) ->
    google.calendar('v3').events.insert {
      auth: oauth2Client,
      calendarId: 'primary',
      resource: {
        start: {
          dateTime: date.toISOString()
        },
        end: {
          dateTime: (new Date(date.getTime() + 7200000)).toISOString()
        },
        description: "Laundry use for #{user}",
        summary: user
      }
    }, apiWrapper res, (response) ->
      callback(null, response)

deleteAppointment = (robot, res, eid, callback) ->
  getAuthedClient robot, res, (oauth2Client) ->
    google.calendar('v3').events.delete {
      auth: oauth2Client,
      calendarId: 'primary',
      eventId: eid
    }, apiWrapper res, (response) ->
      callback(null)

printAppointment = (appointment, print_id) ->
  start = moment(new Date(appointment.start.date || appointment.start.dateTime)).calendar()
  end = moment(new Date(appointment.end.date || appointment.end.dateTime)).calendar()
  summary = appointment.summary
  id = appointment.id
  result = "*#{summary}*: #{start} until #{end}"
  if print_id
    result += ", ID: #{id}"
  result

module.exports = (robot) ->

  robot.respond /laundry$/, (res) ->
    getAllAppointments robot, res, 10, (err, appointments) ->
      if err?
        res.send "Couldn't fetch appointments."
        return
      response = ""
      for appointment in appointments
        response += (printAppointment appointment, false) + "\n"
      res.send response

  robot.respond /laundry create (.+)$/, (res) ->
    user = res.message.user.name.toLowerCase()
    date = chrono.parseDate res.match[1]
    createAppointment robot, res, user, date, (err, appointment) ->
      if err?
        res.send "Couldn't create event."
        return
      res.send("I created an appointment for you, #{user}:\n" + printAppointment appointment, true)

  robot.respond /laundry delete ([a-zA-Z0-9]+)$/, (res) ->
    deleteAppointment robot, res, res.match[1], (err) ->
      if err?
        res.send "Couldn't delete event."
        return
      res.send "Successfully deleted event."

  robot.respond /laundry next$/, (res) ->
    user = res.message.user.name.toLowerCase()
    getNextAppointment robot, res, user, (err, appointment) ->
      if err?
        res.send "You don't have a next appointment booked."
        return
      res.send(printAppointment appointment, true)

  robot.respond /laundry revoketoken$/, (res) ->
    robot.brain.set 'laundry-calendar-token', null
    res.send "Token revoked."

  robot.respond /laundry storetoken (.+)$/, (res) ->
    storeToken robot, res, res.match[1], () ->
      res.send "Token stored! Please try your command again."