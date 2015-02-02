class CrossFrameDiscovery
  @defaults:
    # Origins allowed to communicate on the channel
    origin: '*'

    # When this is true, this bridge will act as a server and, similar to DHCP,
    # offer to connect to bridges in other frames it discovers.
    server: false

  # Accepts a target window and an object of options. The window provided will
  # act as a starting point for discovering other windows.
  constructor: (@target, options={}) ->
    @server = options.server or CrossFrameDiscovery.defaults.server
    @origin = options.origin or CrossFrameDiscovery.defaults.origin

  startDiscovery: (onDiscovery) ->
    # Find other frames that run the same discovery mechanism. Sends a beacon
    # and listens for beacons.
    #
    # Parameters:
    # onDiscovery: (source, origin, token) -> ()
    #   When two frames discover each other, onDiscovery will be called on both
    #   sides with the same token string.
    #   <this> will be bound to the CrossFrameDiscovery instance.
    @onDiscovery = onDiscovery

    # Listen to discovery messages from other frames
    @target.addEventListener('message', this._onMessage, false)

    # Send a discovery message to other frames to create channels
    this._beacon()
    return

  stopDiscovery: =>
    # Remove the listener for discovery messages
    @target.removeEventListener('message', this._onMessage)
    return


  # Send out a beacon to discover frames to connect with
  _beacon: ->
    beaconMessage = if @server
      '__cross_frame_dhcp_offer'
    else
      '__cross_frame_dhcp_discovery'

    # Starting at the top window, walk through all frames, and ping each frame
    # that is not our own.
    queue = [@target.top]
    while queue.length
      parent = queue.shift()
      if parent isnt @target
        parent.postMessage beaconMessage, @origin
      for child in parent.frames
        queue.push child
    return


  _onMessage: (e) =>
    {source, origin, data} = e.originalEvent

    # Fix for local testing (needed at least in Firefox 34.0)
    if origin is 'null'
      origin = '*'

    # Check if the message is at all related to our discovery mechanism
    match = data.match? /^__cross_frame_dhcp_(discovery|offer|request|ack)(:\d+)?$/
    return unless match

    # Read message type and optional token from message data
    messageType = match[1]
    token = match[2]

    # Process the received message
    {reply, discovered, token} = this._processMessage(messageType, token)
    if reply?
      source.postMessage '__cross_frame_dhcp_' + reply, origin
    if discovered is true
      @onDiscovery(source, origin, token)

    return

  _processMessage: (messageType, token) ->
    # Process an incoming message, returns:
    # - a reply message
    # - whether the discovery has completed
    reply = null
    discovered = false

    if @server # We are configured as server
      if messageType is 'discovery'
        # A client joined the party. Offer it to connect.
        reply = 'offer'
      else if messageType is 'request'
        # Create a channel with random identifier
        token = ':' + ('' + Math.random()).replace(/\D/g, '')
        reply = 'ack' + token
        discovered = true
    else # We are configured as a client
      if messageType is 'offer'
        # The server joined the party, or replied to our discovery message.
        # Request it to set up a channel if we did not already do so.
        unless @requestInProgress?
          @requestInProgress = true # prevent creating two channels
          reply = 'request'
      else if messageType is 'ack'
        # The other side opened a channel to us. We note its scope and create
        # a matching channel end on this side.
        @requestInProgress = false # value should not actually matter anymore.
        discovered = true
    return {reply: reply, discovered: discovered, token: token}

angular?.module('h').value('CrossFrameDiscovery', CrossFrameDiscovery)
