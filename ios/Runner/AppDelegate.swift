import Flutter
import UIKit
import UserNotifications
import BackgroundTasks

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Request notification permissions for iOS
        requestNotificationPermissions()
        
        // Register for background fetch
        setupBackgroundFetch()
        
        // Register background tasks
        registerBackgroundTasks()
        
        print("MHF Log Shield iOS App Launched")
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Background Tasks Registration
    private func registerBackgroundTasks() {
        if #available(iOS 13.0, *) {
            // Register background app refresh task
            BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.mhf.logshield.refresh", 
                                           using: nil) { task in
                self.handleAppRefresh(task: task as! BGAppRefreshTask)
            }
            
            // Register background processing task
            BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.mhf.logshield.backgroundsync", 
                                           using: nil) { task in
                self.handleBackgroundProcessing(task: task as! BGProcessingTask)
            }
            
            // Schedule initial background tasks
            scheduleAppRefresh()
            scheduleBackgroundProcessing()
        }
    }
    
    // MARK: - Background Task Handlers
    @available(iOS 13.0, *)
    private func handleAppRefresh(task: BGAppRefreshTask) {
        print("iOS App Refresh task triggered")
        
        // Schedule the next refresh
        scheduleAppRefresh()
        
        // Process logs
        processBackgroundLogs { success in
            task.setTaskCompleted(success: success)
            print("App refresh task completed with success: \(success)")
        }
    }
    
    @available(iOS 13.0, *)
    private func handleBackgroundProcessing(task: BGProcessingTask) {
        print("iOS Background Processing task triggered")
        
        // Process logs with more time
        processBackgroundLogs { success in
            task.setTaskCompleted(success: success)
            print("Background processing task completed with success: \(success)")
        }
    }
    
    // MARK: - Schedule Background Tasks
    private func scheduleAppRefresh() {
        if #available(iOS 13.0, *) {
            let request = BGAppRefreshTaskRequest(identifier: "com.mhf.logshield.refresh")
            // Schedule for 15 minutes from now (minimum)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            
            do {
                try BGTaskScheduler.shared.submit(request)
                print("✅ Scheduled background app refresh")
            } catch {
                print("❌ Could not schedule app refresh: \(error)")
            }
        }
    }
    
    private func scheduleBackgroundProcessing() {
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: "com.mhf.logshield.backgroundsync")
            // Schedule for 30 minutes from now
            request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
            // Requires network connectivity
            request.requiresNetworkConnectivity = true
            // Optional: Requires external power for longer tasks
            request.requiresExternalPower = false
            
            do {
                try BGTaskScheduler.shared.submit(request)
                print("✅ Scheduled background processing")
            } catch {
                print("❌ Could not schedule background processing: \(error)")
            }
        }
    }
    
    // MARK: - Process Background Logs
    private func processBackgroundLogs(completion: @escaping (Bool) -> Void) {
        print("Processing background logs...")
        
        // Ensure we're on main thread for Flutter
        DispatchQueue.main.async {
            guard let controller = self.window?.rootViewController as? FlutterViewController else {
                print("❌ No FlutterViewController found")
                completion(false)
                return
            }
            
            let channel = FlutterMethodChannel(
                name: "com.mhf.logshield/background",
                binaryMessenger: controller.binaryMessenger
            )
            
            channel.invokeMethod("processBackgroundTask", arguments: nil) { result in
                if let success = result as? Bool {
                    print("Background task result from Flutter: \(success)")
                    completion(success)
                } else {
                    print("Invalid result from Flutter: \(String(describing: result))")
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - Notification Permissions
    private func requestNotificationPermissions() {
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    print("Notification permissions granted")
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Background Fetch Setup (legacy iOS < 13)
    private func setupBackgroundFetch() {
        // iOS will call performFetchWithCompletionHandler when it grants background time
        // Set minimum background fetch interval (minimum is 15 minutes)
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        print("Background fetch interval set to minimum")
    }
    
    // MARK: - Background Fetch Handler (legacy iOS < 13)
    override func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("iOS Legacy Background fetch triggered")
        
        // For iOS 12 and earlier, use background fetch
        processBackgroundLogs { success in
            if success {
                print("Legacy background fetch completed successfully")
                completionHandler(.newData)
            } else {
                print("Legacy background fetch failed or no data")
                completionHandler(.noData)
            }
        }
    }
    
    // MARK: - Handle App Termination
    override func applicationWillTerminate(_ application: UIApplication) {
        print("App will terminate - attempting to send final logs")
        
        // Try to send final logs synchronously before termination
        let semaphore = DispatchSemaphore(value: 0)
        var finalSuccess = false
        
        processBackgroundLogs { success in
            finalSuccess = success
            semaphore.signal()
        }
        
        // Wait up to 2 seconds for completion
        _ = semaphore.wait(timeout: .now() + 2.0)
        print("Final log sync before termination: \(finalSuccess ? "Success" : "Failed")")
    }
    
    // MARK: - Handle Background/Active Transitions
    override func applicationDidEnterBackground(_ application: UIApplication) {
        print("App entered background")
        
        // Schedule background tasks when app enters background
        if #available(iOS 13.0, *) {
            scheduleAppRefresh()
            scheduleBackgroundProcessing()
        }
    }
    
    override func applicationWillEnterForeground(_ application: UIApplication) {
        print("App will enter foreground")
    }
    
    override func applicationDidBecomeActive(_ application: UIApplication) {
        print("App became active")
    }
    
    // MARK: - Push Notifications
    override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(token)")
    }
    
    override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}