
struct IgIdent {
    var touch = 05
    var text = "Hello, World! IgIDENT 1.0.12"
}
//
//  IGController
//  Kitura-Starter
//
//  Created by william donner on 2/10/17.
//
//

import Foundation
import Kitura
import KituraNet

import KituraRequest
import KituraSession

import SwiftyJSON
import LoggerAPI
import CloudFoundryEnv

import CloudFoundryDeploymentTracker
import IgBluCommons


enum SMaxxResponseCode: Int {
    case success = 200
    case workerNotActive = 538
    case duplicate = 539
    case badMemberID = 533
    case noData = 541
    case waiting = 542
    case noToken = 545
}
/// Instagram Authentication
///  inspired by Kitura Credentials and the google and facebook plugins
///  however, this is not a plugin and it uses NSURLSession to communicate with Instagram, not the Kitura HTTP library

let serverConfigIdent = ServerConfig(  version: "0.998923",
                                       title: "IGBLUEIDENT",
                                       description: "/instagram older",
                                       ident : "https://igblue.mybluemix.net")

extension   StandardController {
    public convenience init() throws {
        try self.init(serverConfigIdent)
        CloudFoundryDeploymentTracker(repositoryURL: "https://github.com/IBM-Bluemix/Kitura-Starter.git", codeVersion: nil).track()
        
    }
}
open class InstagramController : StandardController {
    
    static let appscope = "basic+likes+comments+relationships+follower_list+public_content"
    static let igVerificationToken = "zzABCDEFG0123456789zz"
    
    fileprivate var clientId : String = ""
    fileprivate var clientSecret : String = ""
    fileprivate var callbackUrl : String = ""
    fileprivate var callbackPostUrl : String = ""
    
    var fullyInitialized = false
    
    // these all come from the config file
    //var instagramCredentials : InstagramController!
    var igApps: [String:[String:String]] = [:]
    var usersHack: [String:[String:String]] = [:]
    var globalProps: [String:String] = [:]
    var globalRoutingComponents : [String] = []
    
    //MARK:- Globals
    let boottime = Date()
    var sess: SessionState?
    var session: Session?
    var activeRoutes:[[String:String]] = []
    
    // called when fully started, load all the specials
    func controllerIsFullyStarted() {
        
        //loadIGData()
        // loadGlobalzData(config: controller.configurl)
        
        self.fullyInitialized = true
        
    }
    public init?(tag:String ) throws  {
        
        let cf =   try handleconfig()
        
        try super.init(serverConfigIdent)
        
        globalData.localConfig = cf
        
        guard let _ =  globalData.localConfig ["grandConfig"] as? String ,
            let tag = globalProps["appcreds"]  else { return nil }
        
        let x = igApps[tag]
        
        guard let xx = x else { return nil }
        
        self.clientId = xx["clientid"]!
        self.clientSecret = xx["secret"]!
        self.callbackUrl = xx["callback"]!
        self.callbackPostUrl = xx["subcallback"]!
        
    }// init
    
    public  func start()   {
        
        
        // confirm all is good by going to get our IP address on net
        InstagramController.discoverIpAddress() { ip in
            let serverip = ip
            self.setupBasicRoutes( self.router)
            
            //controller.port
            let srv = Kitura.addHTTPServer(onPort:self.port , with: self.router)
            srv.started {
                self.controllerIsFullyStarted()
                Log.info("--Server \(serverip) version \(self.serverConfig.softwareversion) started on '\(self.url)' from     ")
            }
            srv.failed {status in
                Log.error("--Server \(serverip) version \(self.serverConfig.softwareversion) FAILED TO START '\(self.url)' status \(status)   ")
                exit(1)
            }
            // Start server
            Kitura.run()
        }// discover
    }//start
    
    
}
extension InstagramController  {
    //MARK:- Create Singleton Controller, Router and Add Routes
    
    open func setupBasicRoutes(_ router:Router) {
        /// offer public files here - it is used internally to load files at startup as well
        
        
        // Basic GET request
        router.get("/", handler: getJSON)
        
        
        // JSON Get request
        router.get("/json", handler: getJSON)
        
        /// offer public files here - it is used internally to load files at startup as well
        router.all("/fs", middleware: StaticFileServer(path: "./public/"))  // normally ./public into self rel
        
        // Initialising our KituraSession
        router.all(middleware:Session(secret: "kitura_session"))
        setupIGPostCallbackRoutes(router: router)
        setupIGRoutes(router: router)
        setupProceduresRoutes(router:router)
        //movedsetupReportingRoutes(router: router)
        
        /// standard routes come last
        router.get("/") { request, response, next in
            self.STEP_ONE(response) // will redirect to IG
        }
        
        // JSON Get request
        router.get("/json", handler: getJSON)
        
        router.get("/log") { request, response, next in
            let qp = request.queryParameters
            response.headers["Content-Type"] = "application/json; charset=utf-8"
            var jsonResponse = JSON(["logged":"\(qp)"])
            Log.info("LOGLINE \(qp)")
            jsonResponse["timenow"].stringValue = "\(Date())"
            try response.status(.OK).send(json: jsonResponse).end()
            
            self.globalData.apic.getIn += 1
        }
        
        /// this path allows other servers to obtain the instagram goodies so they can make instagram callls instead of us
        /// TODO: - add more security possibly even dhecking ip addresses against a whitelist
        
        router.get("/igtoken/:userid") {   request, response, next in
            // -- standard api token userid validation
            guard self.fullyInitialized else { self.sendCallAgainSoon(response); return }
            guard let smtoken = request.queryParameters["smtoken"] else { return  self.missingID(response) }
            guard let loggedOnData = self.globalData.usersLoggedOn[smtoken]  else {  return  self.missingID(response)  }
            guard let userid = loggedOnData["userid"],let uid = request.parameters["userid"], uid == userid else { return  self.missingID(response)  }
            // -- end standard verification
            guard let token = loggedOnData["token"] else { return  self.missingID(response)  }
            response.headers["Content-Type"] = "application/json; charset=utf-8"
            var jsonResponse = JSON(["status":200 ,"ig-token":token,"ig-userid":userid])
            jsonResponse["timenow"].stringValue = "\(Date())"
            try? response.status(.OK).send(json: jsonResponse).end()
            
            self.globalData.apic.getIn += 1
            
        }
    }
    
    
    func setupIGRoutes(router:Router) {
        ///
        // MARK: Callback GETs and POSTs from IG come here
        ///
        router.get("/logout")  { request, response, next in
            guard let smtoken = request.queryParameters["smtoken"] else {
                return  self.missingID(response)
            }
            let loggedOnData =  self.globalData.usersLoggedOn[smtoken]
            if loggedOnData != nil {
                self.globalData.usersLoggedOn[smtoken] = nil
                response.headers["Content-Type"] = "text/plain; charset=utf-8"
                try response.send("logged out from here").end()
                return
            }
            response.headers["Content-Type"] = "text/plain; charset=utf-8"
            try response.send("not logged on").end()
        }
        
        // This should get the ball rolling
        router.get("/showlogin")  { request, response, next in
            self.globalData.apic.getIn += 1
            
            self.STEP_ONE(response) // will redirect to IG
            
            //next()
        }
        
        
        router.get("/authcallback" ) { request, response, next in
            //Log.error("************* /authcallback will authenticate ")
            self.STEP_TWO (request, response: response ) { status in
                if status != 200 { Log.error("Back from STEP_TWO status \(status) ") }
            }
            
            //next()
        }
        router.get("/unwindor" ) { request, response, next in
            // just a means of unwinding after login , with data passed via queryparam
            self.STEP_THREE (request, response: response )
            do {
                let id = request.queryParameters["smaxx-id"] ?? "no id"
                let smtoken = request.queryParameters["smaxx-token"] ?? "no smtoken"
                let name = request.queryParameters["smaxx-name"] ?? "no smname"
                let pic = request.queryParameters["smaxx-pic"] ?? "no smpic"
                let dic = ["status":SMaxxResponseCode.success    ,"smaxx-id":id   , "smaxx-pic":pic   ,"smaxx-token":smtoken   ,"smaxx-name":name   ] as    [String:Any]
                
                response.headers["Content-Type"] = "text/plain; charset=utf-8"
                try response.status(HTTPStatusCode.OK).send(dic.description).end()
                
                //                response.headers["Content-Type"] = "application/json; charset=utf-8"
                //                try response.status(HTTPStatusCode.OK).send(JSON(dic).description).end()
                
            }
            catch {
                Log.error("Failed /authcallback redirect \(error)")
            }
            //next()
        }
        
        
        // temp
        router.get("/subscribe/:who" ){ request, response, next in
            self.globalData.apic.getIn += 1
            
            guard let who = request.parameters["who"] else { return  self.missingID(response)  }
            
            //        guard let token = request.parameters["token"] else { return  missingID(response)  }
            //        guard let rid = request.parameters["id"] else { return  missingID(response)  }
            
            let ix = self.usersHack[who]
            guard let x = ix else {
                return  self.missingID(response)
            }
            
            guard let _ = x["userid"], let token = x["apitoken"] else {
                return  self.missingID(response)
            }
            
            //
            self.make_subscription(response,access_token: token,subscriptionVerificationToken: InstagramController.igVerificationToken)
            
            //next()
        }
        
        ///
        // MARK:- Handles any errors that get set
        ///
        router.error { request, response, next in
            response.headers["Content-Type"] = "text/plain; charset=utf-8"
            do {
                let errorDescription: String
                if let error = response.error {
                    errorDescription = "\(error)"
                } else {
                    errorDescription = "Unknown error"
                }
                try response.send("Caught the error: \(errorDescription)").end()
            }
            catch {
                Log.error("Failed to send response \(error)")
            }
            next()
        }
        
        ///
        // MARK:- A custom Not found handler
        ///
        // A custom Not found handler
        router.all { request, response, next in
            if  response.statusCode == .notFound  {
                // Remove this wrapping if statement, if you want to handle requests to / as well
                //if  request.originalUrl != "/"  &&  request.originalUrl != ""  {
                
                do {
                    try response.send("Route \( request.originalURL) not found  ").end()
                }
                catch {
                    Log.error("Failed to send response \(error)")
                }
                //}
            }
            next()
        }
        
        
    }// end of setupRoutes
    
    
    
    // called from main - need to wait for server to start before this gets called to load data into DB
    //@discardableResult   func loadIGData()  {
    //let tag = globalProps["appcreds"] ?? "no app creds"
    //instagramCredentials = instagramControllerFor(tag: tag)  // or DEV
    //
    //}
}
extension InstagramController {
    
    struct TraceLog {
        static var buffer :[String] = []
        static func bufrd_clear( ) {
            buffer = []
        }
        static func bufrd_print(_ s:String) {
            buffer += [s]
        }
        static func bufrd_print(_ s:[String]) {
            buffer += s
        }
        static func bufrd_contents()->[String] {
            return buffer
        }
    }
    
    public class func discoverIpAddress(completion:@escaping (String) ->()) {
        KituraRequest.request(.get, "https://api.ipify.org?format=json").response {
            request, response, data, error in
            if let data = data {
                let jsonBody = JSON(data: data)
                if let ip = jsonBody["ip"].string {
                    completion(ip )
                }
                else {
                    fatalError("no ip address for this Kitura Server instance, status is \(error)")
                }
            }
        }
    }
    
    ////
    //MARK: Configuration process starts right here:::
    
    func  loadConfig(_ configurl:String,completion:@escaping (Int)->()){
        
        var qurl:[Int:[String]] = [:]
        var purl:[Int:[String]] = [:]
        var lurl:[Int:[String]] = [:]
        var nurl:[Int:[String]] = [:]
        var name:[Int:[String]] = [:]
        
        func dprint(_ s:String) {
            //            if localConfig["debugPrint"] != nil {
            //                print(s)
            //            }
        }
        InstagramController.fetch(configurl) { code,data in
            guard code == 200 else {
                Log.error("Could not open configurl \(configurl)")
                exit(1)
            }
            if let ldata = data {
                
                //let jsa = JSON(data:ldata).arrayValue
                if let d = JSON(data:ldata).dictionary {
                    if let comment = d["comment"]?.string {
                        dprint("!!\(comment)")
                    }
                    if let globalz = d["globalz"]?.dictionary {
                        
                        // copy the dictionary into place
                        var newv :[String:String] = [:]
                        for (key,val) in globalz {
                            if key == "components" {
                                // break pipe delimited components up into pieces
                                self.globalRoutingComponents = (val.stringValue).components(separatedBy: "|")
                            } else {
                                newv[key] = val.stringValue
                            }
                        }
                        self.globalProps = newv //as! [String : [String : String]]
                        dprint("!!loaded \(newv.count) global properties")
                    }
                    if let igapps = d["igapps"]?.dictionary {
                        
                        var uhack:[String:[String:String]] = [:]
                        // copy the dictionary into place
                        var newv :[String:String] = [:]
                        for (key,val) in igapps {
                            let dict = val.dictionaryValue // get the dictionary
                            for (key2,val2) in dict {
                                newv[key2] = val2.stringValue
                            }
                            uhack[key] = newv
                        }
                        self.igApps = uhack //as! [String : [String : String]]
                        dprint("!!loaded \(uhack.count) app properties")
                    }
                    if let usershack = d["usershack"]?.dictionary {
                        
                        var uhack:[String:[String:String]] = [:]
                        // copy the dictionary into place
                        var newv :[String:String] = [:]
                        for (key,val) in usershack {
                            let dict = val.dictionaryValue // get the dictionary
                            for (key2,val2) in dict {
                                newv[key2] = val2.stringValue
                            }
                            uhack[key] = newv
                        }
                        self.usersHack = uhack //as! [String : [String : String]]
                        dprint("!!loaded \(uhack.count) user proxies")
                    }
                    
                }//has json dict
            }//has datat
            completion(200)
        }// fetch closure
    } // end of loadMasterConfigFrom
    
    
    func unknownOP(_ response:RouterResponse) {
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        var jsonResponse = JSON(["status":405 ,"results":"unknown OP"])
        jsonResponse["timenow"].stringValue = "\(Date())"
        try? response.status(.notAcceptable).send(json: jsonResponse).end()
    }
    
    
    
    
    public func getJSON(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        
        globalData.apic.getIn += 1
        let out = ["coming-soon":"igIdent"]
        try finishJSONStatusResponse(out, request: request, response: response,next:next)
        
    }
    
    
    
    static func innerHTTP( requestOptions:inout [ClientRequest.Options],completion:@escaping (Int,Data?) ->()) {
        //print ("innerhttp \(requestOptions)")
        
        //request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var responseBody = Data()
        let req = HTTP.request(requestOptions) { response in
            if let response = response {
                guard response.statusCode == .OK else {
                    _ = try? response.readAllData(into: &responseBody)
                    completion(404,responseBody)
                    return }
                _ = try? response.readAllData(into: &responseBody)
                completion(200,responseBody)
            }
        }
        
        req.end()
    }
    static   func fetch(_ urlstr: String, completion:@escaping (Int,Data?) ->()) {/// makes http request outbund
        var requestOptions: [ClientRequest.Options] = ClientRequest.parse(urlstr)
        let headers = ["Content-Type": "application/json"]
        requestOptions.append(.headers(headers))
        innerHTTP(requestOptions: &requestOptions,completion:completion)
    }
}

extension InstagramController {
    
    // all require ?smtoken
    func setupProceduresRoutes(router:Router) {
        router.get("/users",handler:showUsers)
        router.get("/apps",handler:showApps)
        
        
        
        /// this path will be in a different server, it is used as a relay tester
        
        router.get("/relay/:userid") {   request, response, next in
            // -- standard api token userid validation
            guard self.fullyInitialized else { self.sendCallAgainSoon(response); return }
            guard let smtoken = request.queryParameters["smtoken"],let userid = request.parameters["userid"] else { return  self.missingID(response) }
            
            /// now make remote call to .... /igtoken/:userid"
            
            let fetchurl  = self.url + "/igtoken/\(userid)?smtoken=\(smtoken)"
            let escapedFetchURL = fetchurl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "URL-MUCKED"
            let starttime = Date()
            
            InstagramController.fetch ( escapedFetchURL,
                                        //fetch(  path, method: method, body: nil, schema: schema, host:host, port: portno,
                completion:   { status, data in
                    
                    response.headers["Content-Type"] = "application/json; charset=utf-8"
                    var jsonResponse = JSON(["fetchedStatus":status ])
                    
                    jsonResponse["timenow"].stringValue = "\(starttime)"
                    let elapsed:TimeInterval =  Date().timeIntervalSince(starttime)
                    jsonResponse["URLtoFetch"].stringValue = fetchurl
                    jsonResponse["originalURL"].stringValue = request.originalURL
                    jsonResponse["fetchedMsTime"].floatValue = Float( elapsed * 1000.0 )
                    if let data = data {
                        let bycount = data.count
                        jsonResponse["fetchByteCount"].intValue =  bycount
                        // see if we have any json
                        let _js =  JSON(data:data)
                        if let jsdict = _js.dictionaryObject
                        {
                            
                            jsonResponse["fetchedResponse "].dictionaryObject = jsdict
                        }
                    }
                    try? response.status(.OK).send(json:jsonResponse).end()
            } )
        } /// relay routw
        
        
    }// setup routes
    
    ///////////
    
    func showApps(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let smtoken = request.queryParameters["smtoken"] else {  return  self.missingID(response) }
        guard  self.globalData.usersLoggedOn[smtoken] != nil  else { return  self.missingID(response) }
        
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        var jsonResponse = JSON(["status":200 ,"ig-apps":igApps])
        jsonResponse["timenow"].stringValue = "\(Date())"
        try? response.status(.OK).send(json: jsonResponse).end()
    }
    func showUsers(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let smtoken = request.queryParameters["smtoken"] else {  return  self.missingID(response) }
        guard  self.globalData.usersLoggedOn[smtoken] != nil  else { return  self.missingID(response) }
        
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        var jsonResponse = JSON(["status":200 ,"users-in-hackmode":usersHack,"users-logged-on":globalData.usersLoggedOn])
        jsonResponse["timenow"].stringValue = "\(Date())"
        try? response.status(.OK).send(json: jsonResponse).end()
    }
    //  ..../worker/:who/:what?smtoken=
    func runWorkerCycle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        // -- standard api token userid validation
        guard self.fullyInitialized else { sendCallAgainSoon(response); return }
        guard let smtoken = request.queryParameters["smtoken"] else { return  self.missingID(response) }
        guard let loggedOnData = self.globalData.usersLoggedOn[smtoken]  else {  return  self.missingID(response)  }
        guard let userid = loggedOnData["userid"],let uid = request.parameters["userid"], uid == userid else { return  missingID(response)  }
        // -- end standard verification
        guard let token = loggedOnData["token"] else { return  missingID(response)  }
        
        
        /// first shot is to run this synchronously
        
        
        
        guard let what = request.parameters["what"] else { return  unknownOP(response)  }
        switch what {
            
        case "json" :
            basicDrain(id: userid, token: token, completion: {status,html, dict in
                
                response.headers["Content-Type"] = "application/json; charset=utf-8"
                let edict = ["status":status ,"payload":dict,"serverURL":self .url,"time-of-report":"\(Date())"] as [String : Any]
                let jsonResponse = JSON(edict)
                try? response.status(.OK).send(json: jsonResponse).end()
            })
        case "plain" :
            basicDrain(id: userid, token: token, completion: {status,html,dict in
                
                response.headers["Content-Type"] = "text/html"
                let edict = ["status":status ,"payload":dict,"serverURL":self.url,"time-of-report":"\(Date())"] as [String : Any]
                let html = self.makeHTMLfromDict(edict)
                try? response.status(.OK).send(html).end()
            })
        default: break
        }
    }
    
    public func makeHTMLfromDict(_ dict:[String:Any]) -> String {
        
        var html = ""
        
        if let timeofreport = dict["time-of-report"] as? String ,
            let status = dict["status"]  as? Int,
            let serverurl = dict["serverURL"] as? String ,
            let payload = dict["payload"] as? [String:Any]{
            
            if let apicalls = payload["api-calls"] as? Int,
                let elapsed = payload ["elapsed-secs"]as? String ,
                let user = payload ["user"] as? String ,//whoshotmedia
                let data  = payload["data"] as? [String:Any],
                let operation = payload["operation"] as? String {
                
                if let followedby = data["followed-by"] as? [[String:Any]],
                    let following = data["following"] as? [[String:Any]],
                    let mediarecent = data["media-recent"] as? [[String:Any]],
                    let userinfo = data["userinfo"] as? [String:Any] {
                    
                    if let followedbycount = userinfo["followed-by-count"] as? Int,
                        let mediacount = userinfo["media-count"] as? Int,
                        let followscount = userinfo["follows-count"] as? Int,
                        let fullname = userinfo["fn"] as? String
                    {
                        // emit payload header
                        
                        html.append("<ul class=topheader ><h2>Report for Instagram user \(user)-\(fullname) \(timeofreport)</h2> \n")
                        html.append("<li> operation: \(operation)  </li>\n")
                        html.append("<li> serverURL: \(serverurl) </li>\n")
                        html.append("<li> apicalls: \(apicalls) </li>\n")
                        html.append("<li> elapsed: \(elapsed) </li>\n")
                        html.append("<li> status: \(status) </li>\n")
                        html.append("<li> followedbycount: \(followedbycount) </li>\n")
                        html.append("<li> mediacount: \(mediacount) </li>\n")
                        html.append("<li> followscount: \(followscount) </li>\n")
                        html.append("</ul>\n")
                        // thru the followedby data
                        
                        html.append("<ul class=followedby ><h3>followed by</h3>\n")
                        for fb in followedby {
                            if let id = fb["id"] as? String,
                                let fn = fb["fn"] as? String,
                                let pic = fb["pic"] as? String,
                                let _ = fb["un"] as? String {
                                html.append("<li> followedby: \(id)-\(fn) <img width=30 src='\(pic)' /></li>\n")
                            }
                        }
                        html.append("</ul>\n")
                        // thru the following data
                        
                        html.append("<ul class=following ><h3>following</h3>\n")
                        for fb in following {
                            if let id = fb["id"] as? String,
                                let fn = fb["fn"] as? String,
                                let pic = fb["pic"] as? String,
                                let _ = fb["un"] as? String {
                                html.append("<li> following: \(id)-\(fn) <img width=30 src='\(pic)' /></li>\n")
                            }
                        }
                        html.append("</ul>\n")
                        // thru the mediarecent data
                        
                        html.append("<ul class=media ><h3>recent media</h3>\n")
                        for mr in mediarecent {
                            if let likes = mr["likes"] as? [[String:Any]],
                                let comments = mr["comments"] as? [[String:Any]],
                                let ct = mr["ct"] as? String,
                                let text = mr["text"] as? String,
                                let likescount = mr["likes-count"] as? Int,
                                let commentscount = mr["comments-count"] as? Int,
                                let filter = mr["filter"] as? String,
                                let link = mr["link"] as? String,
                                let imgurl = mr["imgurl"] as? String{
                                html.append("<div style='margin:20px'><ul  class=mediaitem ><span style='margin:30px'><b>\(text)</b> <a href='\(link)'><img width=44 src='\(imgurl)'/></a></span>\n")
                                // emit about the media
                                html.append("<li> time: \(ct) </li>\n")
                                html.append("<li> filter: \(filter) </li>\n")
                                html.append("<li> commentscount: \(commentscount) </li>\n")
                                html.append("<li> likescount: \(likescount) </li>\n")
                                // html.append("<ul  class=comments >\n")
                                // thru the comments data
                                for comment in comments {
                                    if let from = comment ["from"] as? String,
                                        let _ = comment ["pic"] as? String,
                                        let comm = comment ["comment"] as? String,
                                        let un = comment ["u"] as? String,
                                        let _ = comment ["userid"] as? String {
                                        
                                        html.append("<li> comment: \(from)-\(un) \(comm)</li>\n")
                                    }
                                }
                                
                                // html.append("</ul>\n")
                                
                                //  html.append("<ul class=likes >\n")
                                
                                // thru the likes data
                                for like in likes {
                                    if let from = like ["from"] as? String,
                                        let un = like ["u"] as? String {
                                        
                                        html.append("<li> like: \(from)-\(un) </li>\n")
                                    }
                                }
                            }
                            html.append("</ul></div>\n")
                        }
                        
                        html.append("</ul>\n")
                    }//massive let
                }
            }
        }
        return html
    }
}



extension InstagramController {
    
    /// OAuth2 steps with Instagram
    
    open func STEP_ONE(_ response: RouterResponse) {
        let cburl = self.callbackUrl + "&nonce=112332123"
        let loc = "https://api.instagram.com/oauth/authorize/?client_id=\(clientId)&redirect_uri=\(cburl)&response_type=code&scope=\(InstagramController.appscope)"
        Log.error("STEP_ONE redirecting to Instagram authorization \(loc)")
        // Log in
        do {
            try response.redirect( loc)
            //completion?(300)
        }
        catch {
            Log.error("Failed to redirect to Instagram login page")
        }
    }
    /// step two: receive request from instagram - has ?code paramater
    open func STEP_TWO (_ request: RouterRequest, response: RouterResponse,   completion:((Int) -> ())?) {
        
        func inner_two(_ code:String ) {
            let cburl = self.callbackUrl + "&nonce=112332133" // deliberat3ly changed
            Log.error("STEP_TWO inner cburl \(cburl) starting with \(code) just received from Instagram")
            /// OK UP TO THIS POINT
            
            //let param = "?client_id=\(clientId)&redirect_uri=\(cburl)&grant_type=authorization_code&client_secret=\(clientSecret)&code=\(code)"
            //https://api.instagram.com/oauth/access_token
            
            
            let params:[String:String] = ["client_id" : "\(clientId)",
                "redirect_uri": cburl ,
                "grant_type": "authorization_code",
                "client_secret": clientSecret,
                "code":"\(code)" ]
            
            KituraRequest.request(.post,
                                  "https://api.instagram.com/oauth/access_token",
                                  parameters: params,
                                  encoding: URLEncoding.default)
                .response {
                    innerrequest, innerresponse, data, error in
                    // do something with data
                    let code = innerresponse?.status
                    if code == 200 {
                        guard   error == nil      else {
                            
                            // bad status but get error messag
                            let mesg = ""
                            Log.error("STEP_TWOBEE post to api.instagram.com/oauth/access_token  Bad Status From Instagram  \(mesg)  \(code)")
                            completion?(code!)
                            return
                        }
                    }
                    
                    let jsonBody = JSON(data: data!)
                    if let token = jsonBody["access_token"].string,
                        let userid = jsonBody["user"]["id"].string,
                        let pic = jsonBody["user"]["profile_picture"].string,
                        let title = jsonBody["user"]["username"].string {
                        Log.info("STEP_TWO Instagram sent back \(token) and \(title)")
                        /// stash these, creating new object if needed
                        
                        let smtoken = "\((userid + token).hashValue)"
                        
                        
                        request.session?["userid"].string = userid
                        request.session?["smtoken"].string = smtoken
                        request.session?["token"].string = token
                        request.session?["title"].string = title
                        request.session?["pic"].string = pic
                        
                        
                        Log.error("STEP_TWOBEE  processInstagramResponse \(request.session)")
                        // w.start(userid,request,response)
                        // see if we can go somewhere interesting
                        
                        let vv:[String:String] = ["userid":userid,"smtoken":smtoken,"token":token]
                        self.globalData.usersLoggedOn[smtoken] = vv
                        ///TODO: when done debugging, dont include userid and token in here, the client has no need
                        let tk = "/unwindor?token=\(token)&userid=\(userid)&smaxx-id=\(userid)&smaxx-token=\(smtoken)&smaxx-name=\(title)&smaxx-pic=\(pic)"
                        do {
                            Log.error("STEP_TWOBEE redirect back to client with \(tk)")
                            try response.redirect(tk)  }
                        catch {
                            Log.error("STEP_TWOBEE   Could not redirect to client \(tk)")
                        }
                    }
                    completion?(200)
            }
        }//inner_two
        /// authenticate starts here
        if let error = request.queryParameters["error"] {
            let error_reason = request.queryParameters["error_reason"]
            let error_description = request.queryParameters["error_message"]
            Log.error("Instagram error \(error) and \(error_reason) - \(error_description)")
        } else
            if let code = request.queryParameters["code"] {
                if let nonce = request.queryParameters["nonce"] {
                    print("--got nonce \(nonce) ")
                }
                inner_two(code)
                
            } else {
                print("--no code")
        }
        
    }// end of step two
    
    
    /// redirect back from IG from the unwindor path
    open  func STEP_THREE (_ request: RouterRequest, response: RouterResponse) {
        //Log.error("STEP_THREE   \( request.queryParams)")
    }
    
    private func rest_rewrite_member_info( completion:@escaping (Int) ->())  {
        
        // must migrate to
        
        //TODO: fetch ( escapedFetchURL,
        //fetch(  path, method: method, body: nil, schema: schema, host:host, port: portno,
        // completion:   { status, data in
        
        //        InstagramController.perform_post_request(schema:"https",
        //                                             host:"api.ipify.org",port:443,
        //                                             path:"?format=json",paramString: "")
        //        { status,body  in
        //            if status == 200 {
        //                let jsonBody = JSON(data: body!)
        //                if let _ = jsonBody["ip"].string {
        completion(200 )
        //                }
        //                else {
        //                    fatalError("no ip address for this Kitura Server instance, status is \(status)")
        //                }
        //            }
    }
    
    
    public func badSub(_ response:RouterResponse,reason:String) {
        Log.error(reason)
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        var jsonResponse = JSON(["status":500 ,"results":reason])
        
        //jsonResponse["serverURL"].stringValue = appEnv.url
        
        jsonResponse["timenow"].stringValue = "\(Date())"
        try? response.status(.notAcceptable).send(json: jsonResponse).end()
    }
    
    /// make subscription
    open func make_subscription (_ outerresponse:RouterResponse, access_token:String, subscriptionVerificationToken:String) {
        
        /// DispatchQueue(label: "com.foo.bar", qos: DispatchQoS.utility).async {
        
        Log.info(">>>>>make_subscription for \(subscriptionVerificationToken) callback is \(self.callbackPostUrl) ")
        
        
        let params:[String:Any] = [
            "access_token" : "\(access_token)",
            "client_id" : "\(self.clientId)",
            "client_secret": "\(self.clientSecret)" ,
            "object": "user",
            "aspect": "media",
            "verify_token": "\(subscriptionVerificationToken)",
            "callback_url":"\(self.callbackPostUrl)" ]
        
        KituraRequest.request(.post,
                              "https://api.instagram.com/v1/subscriptions/",
                              parameters: params,
                              encoding: URLEncoding.default).response {
                                request, response, data, error in
                                // do something with data
                                guard error == nil  else {
                                    self.badSub(outerresponse,reason:"INSTAGRAM SAYS subscriptionPostCallback \(subscriptionVerificationToken) was unsuccessful \(error)")
                                    return
                                }
                                guard  let data = data else {
                                    self.badSub(outerresponse,reason:"INSTAGRAM SAYS subscriptionPostCallback \(subscriptionVerificationToken) returned with no data")
                                    return
                                }
                                
                                let jsonBody = JSON(data: data)
                                let metacode = jsonBody["meta"]["code"].intValue
                                guard metacode == 200 else {
                                    let mess = jsonBody["meta"]["error_message"].stringValue
                                    self.badSub(outerresponse,reason:"INSTAGRAM SAYS subscriptionPostCallback \(subscriptionVerificationToken) was unsuccessful meta \(metacode) \(mess)")
                                    return
                                }
                                self.badSub(outerresponse,reason:"* INSTAGRAM SAYS  subscriptionPostCallback \(subscriptionVerificationToken) successful")
        }// response from immediate post
    }
    //}
}
//// these methods need to run on a different server so they can call and return within a blocking IG call from the main server
//// fortunately they are essentially static and have their own routes

extension InstagramController  {
    func setupIGPostCallbackRoutes(router:Router) {
        
        router.get("/postcallback" ) {
            request, response, next in
            self.handle_igsubscribe_challenge_callback(InstagramController.igVerificationToken,request: request,response: response)
            //next()
        }
        
        router.post("/postcallback") {
            request, response, next in
            self.handle_igsubscribe_post_callback(request,response: response)
            //next()
        }
    }
}
extension InstagramController {
    
    open func handle_igsubscribe_post_callback (_ request: RouterRequest, response: RouterResponse) {
        /// parse out the callback we are getting back, its json
        var userid = "notfound"
        let t = "\(request.body)" // stringify this HORRIBLE
        let a = t.components(separatedBy:"\"object_id\" = ")
        if a.count > 1 {
            let b = a[1].components(separatedBy:";")
            if b.count  > 1 {
                userid = b[0]
            }
        }
        Log.error("---->>>>  post handle_igsubscribe_post_callback for user  \(userid)")
        // member must have access token for instagram api access
        //       MembersCache.getTokenFromID(id: userid) { token in
        //        self.rest_make_worker_for(id: userid, token: token!) {_ in
        //            print("rest make worker for \(userid) \(token!) ")
        //        }
        //        }
    }
    
    /// the get is called in the middle of the post verification
    open func handle_igsubscribe_challenge_callback (_ subscriptionVerificationToken:String ,request: RouterRequest, response: RouterResponse) {
        
        
        /// strip out the challenge parameter and return with this only
        let ps = request.originalURL.components(separatedBy: "?")
        // make dictionary
        var d: [String:String] = [:]
        if ps.count >= 2 {
            let pairs = ps[1].components(separatedBy: "&")
            for pair in pairs {
                let p = pair.components(separatedBy: "=")
                if p.count >= 2 {
                    d[p[0]] = p[1]
                }
            }
            Log.error("---->>>>  get callback for subscriptionVerificationToken  \(subscriptionVerificationToken) dict \(d)")
            
            if d["hub.mode"] ==  "subscribe" {
                if d["hub.verify_token"] == subscriptionVerificationToken {
                    if  let reply = d["hub.challenge"] {
                        response.headers["Content-Type"] = "text/plain; charset=utf-8"
                        let r = response.status(HTTPStatusCode.OK)
                        do {
                            let _ =   try r.send(reply).end()
                            print("-------did send verify response to Instagram")
                            Log.error("------did send verify response to Instagram")
                        }
                        catch {
                            Log.error("could not send verify response to Instagram")
                        }
                        Log.info("Post register GET callback replying with challenge \(reply)")
                        return
                    }
                }
            }
        } // >=2
        else {
            
            Log.error("---->>>>  get callback for subscriptionVerificationToken  \(subscriptionVerificationToken) has no ? args")
        }
    }// get  callbac
}

fileprivate func handleconfig() throws -> [String:Any]  {
    
    func fallback() -> [String:Any] {
        print("cant parse config, falling back to embedded configuration")
        return ["grandConfig":"https://billdonner.com/tr/masterconfig-igblu-DEV.json","softwarenamed":"igblu","debugPrint":"on"]
    }
    
    // open local config file in /public
    /**
    #if os(OSX)
        let configurl = URL(fileURLWithPath:"/Users/williamdonner/igblu/public/config.json")
    #elseif os(Linux)
        let rootDirectory = URL(fileURLWithPath: "\(FileManager().currentDirectoryPath)/public")
        let configurl =  rootDirectory.appendingPathComponent("config.json")
    #endif
    
    let data = try Data(contentsOf: configurl)
    if let config = try JSONSerialization.jsonObject(with:data, options: .allowFragments) as? [String: Any] {
        return  config
    } else {
 */
        return fallback()
   // }
}
