Base = require './base'
microflo = require 'microflo'


# TODO: make this runtime be for every device that supports the same FBCS protocol as MicroFlo
class MicroFloRuntime extends Base
  constructor: (definition) ->
    @connecting = false
    @buffer = []
    @container = null
    super definition

  getElement: -> @container

  setParentElement: (parent) ->
    @container = document.createElement 'container'
    parent.appendChild @container

  setMain: (graph) ->
    if @graph
      # Unsubscribe from previous main graph
      @graph.removeListener 'changeProperties', @updatecontainer

    # Update contents on property changes
    graph.on 'changeProperties', @updatecontainer
    super graph

  connect: ->
    unless @container
      throw new Exception 'Unable to connect without a parent element'
 
#    window.require 'microflo-runtime', (Module) ->
#        console.log 'Emscripten stuff loaded', simulator


    # Let the UI know we're connecting
    @connecting = true
    @emit 'status',
      online: false
      label: 'connecting'

    # Set an ID for targeting purposes
    @container.id = 'preview-container'

    # Update container contents as needed
    @on 'connected', @updatecontainer

    # Setup runtime
    # TODO: remove hardcoding of baudrate and debugLevel
    baudRate = 9600
    debugLevel = 'Error'
    address = @getAddress()
    if address == 'simulator://'
        @setupSimulator
        # FIXME: hook up transport to the runtime
    else
        serialPort = address.replace 'serial://', ''
        @setupRuntime baudRate, serialPort, debugLevel

    # HACK: sends initial message, which hooks up receiving as well
    @onLoaded()

  disconnect: ->
    #@container.removeEventListener 'load', @onLoaded, false

    # Stop listening to messages
    # window.removeEventListener 'message', @onMessage, false

    @emit 'status',
      online: false
      label: 'disconnected'

  setupSimulator: ->
    c = document.createElement 'object'
    c.setAttribute 'type', "image/svg+xml"
    c.setAttribute 'data', "controller_arduino_uno_r3.svg"
    c.id = 'microflo-simulator'
    c.innerHTML = 'No SVG support!'
    @container.appendChild c

    setLed = (On) ->
        controller = document.getElementById("microflo-simulator").contentDocument;
        controller = c.contentDocument;
        ledLight = controller.getElementById "pin13led-light"
        opacity = if On then '1' else '0'
        ledLight.setAttributeNS null, 'opacity', opacity

    runtime = Module['_emscripten_runtime_new']()
    setInterval( () ->
        Module['_emscripten_runtime_run'] runtime
    , 100)

    Module['print'] = (str) ->
      console.log(str);

      # HACK: use a custom I/O backend instead, communicate via host-transport
      tok = str.split " "
      if tok.length > 3 && tok[2].indexOf("::DigitalWrite") != -1
        pin = tok[5].replace("pin=","").replace(",","")
        pin = parseInt pin
        state = tok[6] == "value=ON"
        if pin == 13
          setLed state

  updatecontainer: =>
    return if !@container or !@graph
    # TEMP

  setupRuntime: (baudRate, serialPort, debugLevel) ->
    @microfloGraph = {}
    # FIXME: nasty and racy, should pass callback and only then continue
    @debugLevel = debugLevel
    @getSerial = null
    try
      @getSerial = microflo.serial.openTransport serialPort, baudRate
    catch e
      console.log 'MicroFlo setup:', e

  # Called every time the container has loaded successfully
  onLoaded: =>
    @connecting = false
    @emit 'status',
      online: true
      label: 'connected'
    @emit 'connected'

    # Perform capability discovery
    @send 'runtime', 'getruntime', null

    @flush()

  send: (protocol, command, payload) ->
    msg =
        protocol: protocol
        command: command
        payload: payload
    if @connecting
      @buffer.push msg
      return

    sendFunc = (response) =>
      console.log 'sendFunc', response
      @onMessage { data: response }
    conn = { send: sendFunc }
    try
      microflo.runtime.handleMessage msg, conn, @microfloGraph, @getSerial, @debugLevel
    catch e
      console.log e.stack
      console.log e

  onMessage: (message) =>
    switch message.data.protocol
      when 'runtime' then @recvRuntime message.data.command, message.data.payload
      when 'graph' then @recvGraph message.data.command, message.data.payload
      when 'network' then @recvNetwork message.data.command, message.data.payload
      when 'component' then @recvComponent message.data.command, message.data.payload

  flush: ->
    for item in @buffer
      @send item.protocol, item.command, item.payload
    @buffer = []

module.exports = MicroFloRuntime
