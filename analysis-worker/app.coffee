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
                    @startApp()
                    #, 500
    startApp : ()=>
            client.connect "127.0.0.1:11300", (err,con)=>
                if err
                    console.log "Error connecting to beanstalkd #{err}"

                con.watch @config.tubeName , (err)=>
                    con.reserve (err, job_id, data)=>
                        jsonObject = JSON.parse(JSON.parse(data))
                        @Models.Data.findOne {_id : @objectID(jsonObject["id"])}, (err,data)=> #Find all data
                            if !err
                                if data
                                    #Get the formula for the data found
                                    @Models.Formula.findOne {_id: @objectID(data.formulaid)} , (err,formula)=>
                                        if !err
                                            if formula
                                                matchedStatus = []
                                                for status in formula.statuses.reverse()
                                                    #See if all match conditions
                                                    matchArray = [] #Can use to tele if all true
                                                    matchedDatasets = [] #use to handle occurences 
                                                    #Check individual patterns
                                                    for pattern in status.patterns# Loop through each pattern
                                                        #Need to get pattern for specific data
                                                        if pattern.dataset._id isnt data.id._id.toHexString()
                                                            #This isn't the dataset i want
                                                            continue
                                                        matched = false
                                                        #Matched for single

                                                        factor = pattern.compare.toLowerCase()
                                                        targetValue = pattern.value #Configured in system
                                                        value = data.data# value collected
                                                        matchedDatasets.push pattern.dataset.name
                                                        
                                                        if (factor is "equal")
                                                            if (value is targetValue) or (targetValue is "Not usable")
                                                                matched = true
                                                        else if factor is "more"
                                                            if (parseInt value) > (parseInt targetValue)
                                                                matched = true
                                                        else if factor is "less"
                                                            if (parseInt value) < (parseInt targetValue)
                                                                matched = true
                                                        matchArray.push matched
                                                        
                                                        #If matched, update all occurences
                                                        if matched
                                                            updateOrInsert = (occur, existingOccur, park)=>
                                                                if existingOccur.length > 0
                                                                    @Models.Occurence.update {_id : existingOccur[0]._id}, {$inc : { count : 1}}, (err,data)=>
                                                                        if err
                                                                            console.log err
                                                                        con.destroy job_id , (err)=>
                                                                            @reevaluate()
                                                                            @startApp()
                                                                else
                                                                    @Models.Occurence.insert occur, (err,data)=>
                                                                        if err
                                                                            console.log "inset error err"
                                                                        con.destroy job_id , (err)=>
                                                                            @reevaluate()
                                                                            @startApp()
                                                            #Find all occurences with selected park, statusValue and formula id, and dataset id
                                                            getOccurence = (formula, pattern, status, park)=>

                                                                @Models.Occurence.find({formula : formula._id , status : status.statusValue, dataset : pattern.dataset._id , count :  {$exists : true},  park : park}).toArray (err,existingOccur)=>
                                                                    if !err
                                                                        occur = 
                                                                            formula : formula._id
                                                                            status : status.statusValue
                                                                            dataset : pattern.dataset._id
                                                                            datasetName : pattern.dataset.name
                                                                            count : 1
                                                                            park : park 
                                                                        updateOrInsert(occur , existingOccur , park)
                                                                    else
                                                                        console.err err
                                                            getOccurence(formula, pattern, status, data.park._id)
                                                        else
                                                             #If single pattern matches conditions, insert or update in database
                                                            console.log "No conditions are matched"
                                                            console.log " #{value} #{targetValue} #{factor} #{matched} #{status.statusValue} #{pattern.dataset.name}"

                                                            con.destroy job_id , (err)=>
                                                                @reevaluate()
                                                                @startApp()
                                        else
                                            console.log err
                                else
                                    con.destroy job_id , (err)=>
                                        @reevaluate()
                                        @startApp()
                            else
                                @log err
                            
    reevaluate: ()=>
        #Get all formulas
        @Models.Formula.findOne {"using" : "true"} , (err,formula)=>
            if !err
                if formula
                    for status in formula.statuses.reverse()
                        #Get all patterns
                        matchedStatus = {}
                        patternMatches = []

                        for pattern in status.patterns
                            #Loop through each pattern that has been configured

                            #Get the pattern's dataset and then all ocurrences with this dataset
                            getPattern = (pattern)=>
                                defer = @Q.defer()
                                getDataset = (pattern)=>
                                    defer = @Q.defer()
                                    @Models.Dataset.findOne {_id : @objectID(pattern.dataset._id)}, (err, dataset)=>
                                        if !err
                                            getOccurenceByID = (dataset, pattern, status ,formula )=>
                                                if dataset and pattern and status and formula 
                                                    @Models.Occurence.findOne {dataset : dataset._id.toHexString() , status : status.statusValue , formula : @objectID(formula._id)}, (err,occurences)=>
                                                        if !err
                                                            if occurences
                                                                #If database occurence is more than configured pattern count, then configure true
                                                                if (occurences.count >= pattern.occurences)
                                                                    defer.resolve {status : true, park : occurences.park, occurenceID : occurences._id, reason : occurences["datasetName"]+" ocurrences count( #{occurences.count} ) more than targeted occurences ( #{pattern.occurences} )"}
                                                                else
                                                                    defer.resolve {park : occurences.park, dataset: dataset.name, statusValue: status.statusValue, status : false, reason : "Occurence count(#{occurences.count}) didnt meet Target ocurrence count(#{pattern.occurences})"}
                                                            else
                                                                #console.log "Cannot find entries"
                                                                #console.log {dataset : dataset._id.toHexString() , status : status.statusValue , formula : @objectID(formula._id)}
                                                                defer.resolve {status : false , reason : "Could not find occurence"}
                                                        else
                                                            defer.resolve {status : false}
                                                else
                                                    defer.resolve {status : false}
                                            getOccurenceByID(dataset, pattern, status, formula)
                                        else
                                            defer.resolve {status : false }
                                    return defer.promise
                                getDataset(pattern).then (result)=>
                                    defer.resolve results
                                , (err)=> 
                                    defer.reject err
                                return defer.promise;
                            patternMatches.push getPattern(pattern)
                        @Q.allSettled(patternMatches).then (results)=>
                            parkid = []
                            #console.log results
                            for result in results
                                if result.value.park and (result.value.status is true)
                                    #If rsolved, then update park info
                                    statusValue = status.statusValue.toLowerCase()
                                    color = ""
                                    if statusValue is "high"
                                        color = "red"
                                    else if statusValue is "mild"
                                        color = "yellow"
                                    else if statusValue is "low"
                                        color = "green"
                                    console.log result.value.status 
                                    if result.value.reason
                                        for parkEntryID, index in parkid
                                            if parkEntryID.parkid is result.value.park
                                                parkid[index]["reason"].push result.value.reason
                                            else
                                                parkid.push {reason : [result.value.reason] , parkid : result.value.park}
                                        if parkid.length is 0
                                            parkid.push {reason : [result.value.reason] , parkid : result.value.park}

                                    @Models.Park.findOne {_id : @objectID(result.value.park)}, (err, data)=>
                                        if !err and data
                                            console.log "#{data.parkName[0]} set to status #{color}"
                                    @Models.Park.update {_id : @objectID(result.value.park)} , {$set : { risk : color}}, (err, park)=>
                                        if err
                                            console.log "Error update"
                                    @Models.Occurence.update {_id : result.value.occurenceID},{$set : {count : 0}},(err,data)=>
                                        #if !err and data
                                            #console.log data+" updated "
                                    @Models.Occurence.remove {park : @objectID(result.value.park)}, {w : 1}, (err, removed)=>
                                        #console.log "Removed "+removed
                                else
                                    @Models.Park.update {_id : @objectID(result.value.park)} , {$set : { risk : "green"}}, (err, park)=>
                                        if err
                                            console.log "Error update"

                            #console.log parkid
                            for parkEntry in parkid                         
                                @Models.Park.update {_id : @objectID(parkEntry["parkid"])} , {$set : { reason : parkEntry["reason"]}}, (err, park)=>
                                    console.log "Updated!"
                                

            else            
                console.log err 
    bsPutJob : (tubename, jobdata)=>
        data = JSON.stringify jobdata
        client.connect "127.0.0.1:11300", (err,con)=>
            if err
                console.log "Error connecting to beanstalkd #{err}"
            con.use tubename, (err)=>
                con.put 0, 0, 1, data, (err, job_id)=>
                    console.log "Put job into #{tubename}"
    objectID : (id) =>
        return new ObjectId(id)
    log : (text) =>
        console.log "[#{@config.appname}] @ "+new Date() + " : "+text
   
    initModels : () =>
        @Models.Formula = @mongo.collection("formula")
        @Models.Data = @mongo.collection("data")
        @Models.Park = @mongo.collection("park")
        @Models.Dataset = @mongo.collection("dataset")
        @Models.Occurence = @mongo.collection("occurence")

    sendError: (req,res, errorCode, message)=>
        res.status errorCode
        return res.send {"error" : message}
    sendAdminError: (req,res, message)=>
        res.status 500
        return res.send {"error": message}
    sendContent: (req,res, content)=>
        res.status 200
        return res.json content
new App()
module.exports = App
