mongo = require 'mongodb'
CachedFind = require './index'

mongo.MongoClient.connect 'mongodb://localhost:27017/test', (err, db) ->

	c = db.collection 'cacher'

	cf = new CachedFind(c, {n: $gt: 5})

	find = ->
		cf.get (err, rows) ->
			console.log 'FOUND', arguments

	cf.on 'init', (rows) -> console.log 'init', rows
	cf.on 'error', (err) -> console.log 'error'
	cf.on 'add', find
	cf.on 'remove', find


