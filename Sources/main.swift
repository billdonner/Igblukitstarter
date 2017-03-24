import Foundation
import LoggerAPI
import HeliumLogger 



// IgIdent sub-classes StandardController, hence this deviance from the general pattern of blu ig main servers

do {
    HeliumLogger.use(LoggerMessageType.info)
   let cont = try InstagramController(tag:"PROD")
    if    let controller = cont  {
        controller.setupBasicRoutes(controller.router)
     controller.start()
    }
}
catch let error {
    Log.error(error.localizedDescription)
    Log.error("Oops... something went wrong. Server did not start!")
}
