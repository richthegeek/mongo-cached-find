sift = require 'sift'
MongoOplog = require 'mongo-oplog'
Promise = require 'bluebird'
HashMap = require('hashmap').HashMap
EventEmitter = require('events').EventEmitter

watchers = {}
getWatcher = (collection) ->
	host = collection.db.serverConfig.host
	port = collection.db.serverConfig.port
	address = "mongodb://#{host}:#{port}/local"
	if not watchers[address]
		watchers[address] = new Promise (resolve, reject) ->
			watcher = MongoOplog address
			watcher.tail ->
				resolve watcher

	return watchers[address]

module.exports = class CachedFind extends EventEmitter

	constructor: (@collection, @query = {}, refresh_after_tail = true) ->
		ns = collection.db.databaseName + '.' + collection.collectionName

		@sifter = sift query
		@documents = new HashMap()

		if not refresh_after_tail
			@refresh()

		@watcher = getWatcher(collection)
		@watcher.then (watcher) =>
			@emit 'tailing', watcher

			if refresh_after_tail
				@refresh()

			watcher.on 'insert', (event) =>
				if event.ns is ns
					if @check event.o
						@add event.o
			
			watcher.on 'update', (event) =>
				if event.ns is ns
					if @check event.o
						@add event.o
					else
						@remove event.o._id

			watcher.on 'remove', (event) =>
				if event.ns is ns
					@remove event.o._id

	refresh: (callback) ->
		@query = new Promise (resolve, reject) =>
			@documents.clear()
			@collection.find(@query).each (err, row) =>
				if err
					@emit 'error', err
					callback? err
					reject err

				else if row
					@documents.set row._id, row

				else
					@emit 'init', @documents.values()
					callback? null, @documents.values()
					resolve()

	check: (document) ->
		@sifter.test document

	add: (document) ->
		@documents.set document._id, document
		@emit 'add', document

	remove: (id) ->
		if @documents[id]
			@documents.remove id
			@emit 'remove', id

	get: (cb) ->
		good = => cb null, @documents.values()
		bad = (reason) -> cb reason

		@query.then good, bad
