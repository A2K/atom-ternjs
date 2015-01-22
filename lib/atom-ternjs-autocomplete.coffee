{Provider, Suggestion} = require atom.packages.resolvePackagePath('autocomplete-plus')

_ = require 'underscore-plus'

maxItems = null

module.exports =
class AtomTernjsAutocomplete extends Provider

    exclusive: true
    autocompletePlus: null
    client: null
    suggestionsArr = null
    _editor: null
    _buffer: null
    currentSuggestionIndex: false
    _disposables: null
    documentationView = null
    autocompleteManager = null
    isActive = false

    constructor: (_editor, _buffer, client, autocompletePlus, documentationView) ->
        @autocompletePlus = autocompletePlus
        @_disposables = []
        @suggestionsArr = []
        @client = client
        @_editor = _editor
        @_buffer = _buffer
        @documentationView = documentationView
        super

    init: ->
        @getAutocompletionManager()
        @registerEvents()

    buildSuggestions: ->
        suggestions = []
        prefix = @getPrefix()
        for item, index in @suggestionsArr
            if index == maxItems
                break
            suggestions.push new Suggestion(this, word: item[0], label: item[1], prefix: prefix)
        return suggestions

    callPreBuildSuggestions: (force) ->
        cursor = @_editor.getLastCursor()
        prefix = cursor.getCurrentWordPrefix()
        if force || /^[a-z0-9.\"\']$/i.test(prefix[prefix.length - 1])
          @preBuildSuggestions()
        else
          @cancelAutocompletion()

    getPrefix: ->
        return @prefixOfSelection(@_editor.getLastSelection())

    preBuildSuggestions: ->
        return unless @autocompleteManager
        @suggestionsArr = []
        @checkCompletion().then (data) =>
            if !data?.length
                @cancelAutocompletion()
                return
            prefix = @getPrefix()
            if data.length is 1 and prefix is data[0].name
                @cancelAutocompletion()
                return
            for obj, index in data
                if index == maxItems
                    break
                @suggestionsArr.push [obj.name, obj.type, obj.doc]
            # refresh
            @triggerCompletion()

    triggerCompletion: =>
        @autocompleteManager.runAutocompletion()
        @currentSuggestionIndex = 0
        @setDocumentationContent()

    setDocumentationContent: ->
        return unless @suggestionsArr.length
        @documentationView.setTitle(@suggestionsArr[@currentSuggestionIndex][0], @suggestionsArr[@currentSuggestionIndex][1])
        @documentationView.setContent(@suggestionsArr[@currentSuggestionIndex][2])
        @documentationView.show()

    cancelAutocompletion: ->
        @suggestionsArr = []
        @documentationView.hide()
        return unless @autocompleteManager
        @autocompleteManager.cancel()

    getMaxIndex: ->
        Math.min(maxItems, @suggestionsArr.length)

    update: ->
        @client.update(@_editor.getURI(), @_editor.getText())

    registerEvents: ->
        @_disposables.push @_buffer.onDidStopChanging =>
            _.throttle @update(@_editor), 300
            _.throttle @callPreBuildSuggestions(), 100
        @_disposables.push atom.config.observe('autocomplete-plus.maxSuggestions', => maxItems = atom.config.get('autocomplete-plus.maxSuggestions'))
        @_disposables.push @_editor.onDidChangeCursorPosition (event) =>
            if !event.textChanged
                @cancelAutocompletion()
        @_disposables.push atom.workspace.onDidChangeActivePaneItem =>
            @cancelAutocompletion()
        @_disposables.push @autocompleteManager.emitter.on 'do-select-next', =>
            return unless @isActive
            if ++@currentSuggestionIndex >= @getMaxIndex()
                @currentSuggestionIndex = 0
            @setDocumentationContent()
        @_disposables.push @autocompleteManager.emitter.on 'do-select-previous', =>
            return unless @isActive
            if --@currentSuggestionIndex < 0
                @currentSuggestionIndex = @getMaxIndex() - 1
            @setDocumentationContent()

    unregisterEvents: ->
        for disposable in @_disposables
            disposable.dispose()
        @_disposables = []

    dispose: ->
        @documentationView.hide()
        @unregisterEvents()

    getAutocompletionManager: ->
        for manager in @autocompletePlus.autocompleteManagers
            if manager.editor is @_editor
                @autocompleteManager = manager

    checkCompletion: ->
        cursor = @_editor.getLastCursor()
        position = cursor.getBufferPosition()
        @client.completions(@_editor.getURI(),
            line: position.row
            ch: position.column
            ).then (data) =>
                data.completions
        , (err) ->
            console.log err
