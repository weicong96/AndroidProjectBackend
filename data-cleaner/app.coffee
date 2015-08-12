http = require('http')
config = require("./config")
mongodb = require('mongodb').MongoClient
express = require('express')
bodyParser = require("body-parser")
ObjectId = require('mongodb').ObjectID;
request = require("request")
fs = require("fs")
xml2js = require("xml2js")
client = require('beanstalk_client').Client;
redisClient = require("redis").createClient()
class App
    Models : {}
    constructor : ->
        @config = config
        @Q = require("q")
        @mongo = mongodb.connect @config.mongodb.url,(err, db)=>
            if !err
                if db
                    @mongo = db
                    console.log "Mongodb started"
                    @initModels()
                    #setInterval ()=>
                    #    @setupParks()
                    #, 10 * 1000
                    @setupParks()
    
    objectID : (id) =>
        return new ObjectId(id)
    log : (text) =>
        console.log "[#{@config.appname}] @ "+new Date() + " : "+text
    
    setupParks : ()=>
        console.log "Starting"
        console.log "This program is going to delete all data that is repeated"
        console.log "Definition of repeated : 1) Same datasource 2) Time of current item and previous should have diference less than 1.5hrs 3) Same data value"
        removedAll = []
        request "http://weicong.chickenkiller.com/data", (err,response)=>
            timeCollected = []
            timeCollectedCount = []
            idsToRemove = []
            body = JSON.parse(response.body)
            for park in body
                for dataSource in park["data"]
                    previousItem = null
                    for data in dataSource
                        if previousItem isnt null
                            nowDate = new Date(data["timeCollected"])
                            previousDate = new Date(previousItem["timeCollected"])
                            if(Math.abs(nowDate.getTime() - previousDate.getTime()) < 1.5 * 60 * 60 * 1000) and (data["data"] is previousItem["data"]) and data["id"]["_id"] is previousItem["id"]["_id"]
                                console.log previousItem["data"]
                                console.log "Difference  : "+(nowDate.getTime() - previousDate.getTime())+" #{previousDate} #{nowDate} #{data['_id']} #{data['id']['name']}"
                                idsToRemove.push @objectID(data["_id"])

                        previousItem = data
                #Two problems right now:
                #       -When accumulating times, need to remove repeated timings(due to having three patterns with same datasource)
                #       -Only continue with program after removing the data, or else will cause the time to be defined as rogue points because it does not meet largeest value
                for dataSource in park["data"]
                    uniqueTimesForDS = []
                    for data,index in dataSource
                        if data is null or data is undefined
                            continue
                        formattedDate = new Date(parseInt(new Date(data["timeCollected"]).getTime()/(1000 * 60))*(1000 * 60))
                        data["timeCollected"] = formattedDate
                        index = timeCollected.indexOf(formattedDate.toString())
                        if index == -1  
                            timeCollectedCount.push 1
                            timeCollected.push formattedDate.toString()
                        else
                            if uniqueTimesForDS.indexOf(formattedDate.toString()) == -1
                                uniqueTimesForDS.push formattedDate.toString()
                                timeCollectedCount[index] += 1
                            else
                                idsToRemove.push data["_id"]
                    
                        previousItem = data
            console.log idsToRemove
            largest = Math.min.apply(Math, timeCollectedCount)
            #console.log largest
            console.log timeCollected
            console.log timeCollectedCount
            for park in body
                for dataSource in park["data"]
                    for data in dataSource
                        if idsToRemove.indexOf(data["_id"]) == -1
                            index = timeCollected.indexOf(data["timeCollected"].toString())
                            if index isnt -1
                                #if timeCollectedCount[index] isnt 8 and timeCollectedCount[index] isnt 12
                                if timeCollectedCount[index] isnt 12
                                    idsToRemove.push @objectID(data["_id"])
                                #console.log @objectID(data["_id"])+" is a rogue data point"
            #console.log timeCollected
            @Models.Data.remove {"_id" : {$in : idsToRemove}}, {w:1}, (err,doc)=>
                removedAll.push doc             
                console.log doc
            uncache = true 
            if uncache
                redisClient.del "data_latest", (err, doc)=>
                    console.log "Uncache redis"
                    removedAllTrue = removedAll.every (currentValue)=>
                       if currentValue == 0
                            return true
                        else
                            return false
                    if !removedAllTrue
                        @setupParks()
                        
    initModels : () =>
        @Models.Formula = @mongo.collection("formula")
        @Models.Data = @mongo.collection("data")
        @Models.Park = @mongo.collection("park")
        @Models.Dataset = @mongo.collection("dataset")

    sendError: (req,res, errorCode, message)=>
        res.status errorCode
        return res.send {"error" : message}
    sendAdminError: (req,res, message)=>
        res.status 500
        return res.send {"error": message}
    sendContent: (req,res, content)=>
        res.status 200
        return res.json content
    bsPutJob : (tubename, jobdata)=>
        data = JSON.stringify jobdata
        client.connect "127.0.0.1:11300", (err,con)=>
            if err
                console.log "Error connecting to beanstalkd #{err}"
            con.use tubename, (err)=>
                con.put 0, 0, 1, data, (err, job_id)=>
                    #console.log "Put job into #{tubename} #{job_id}"
new App()
module.exports = App
