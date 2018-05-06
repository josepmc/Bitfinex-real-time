//
//  CurrencyPairViewController.swift
//  BitfinexRealTime
//
//  Created by Ferdinando Messina on 03.05.18.
//  Copyright © 2018 Ferdinando Messina. All rights reserved.
//

import UIKit
import Starscream

class CurrencyPairViewController: UIViewController {

    // Ticker UI
    @IBOutlet weak var socketStatus: UILabel!
    @IBOutlet weak var symbolLabel: UILabel!
    @IBOutlet weak var lastPriceLabel: UILabel!
    @IBOutlet weak var volumeLabel: UILabel!
    @IBOutlet weak var lowPriceLabel: UILabel!
    @IBOutlet weak var highPriceLabel: UILabel!
    @IBOutlet weak var percentage24HoursLabel: UILabel!
    
    // Segmented Control
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    
    // Table View
    @IBOutlet weak var tableView: UITableView!
    
    var currencyPair: CurrencyPair!
    var bitfinexSocket = WebSocket(url: URL(string: "wss://api.bitfinex.com/ws/2")!)
    
    var tickerChannelId: Int?
    
    static func storyboardSegueIdentifier() -> String {
        return "currencyPairSelectedSegue"
    }
    
    func inject(currencyPair aCurrencyPair: CurrencyPair) {
        currencyPair = aCurrencyPair
    }
    
    deinit {
        // We make sure we close the socket when we deinitialize the view controller
        bitfinexSocket.disconnect()
        bitfinexSocket.delegate = nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = currencyPair.readableName
        view.backgroundColor = UIColor(red: 236.0/255, green: 240.0/255, blue: 241.0/255, alpha: 1)
        
        symbolLabel.text = currencyPair.identifier.uppercased()
        
        // SegmentedControl setup
        segmentedControl.addTarget(self,
                                   action: #selector(segmentedControlValueChanged(sender:)),
                                   for: .valueChanged)
        segmentedControl.setTitleTextAttributes([NSAttributedStringKey.font: UIFont.systemFont(ofSize: 16)],
                                                for: .normal)

        // TableView setup
        tableView.delegate = self
        tableView.delegate = self
        
        // Connect the socket
        bitfinexSocket.delegate = self
        bitfinexSocket.connect()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}


// MARK:- WebSocket Delegate
extension CurrencyPairViewController: WebSocketDelegate {

    func websocketDidConnect(socket: WebSocketClient) {
        print("BitfinexWebSocket is now connected")
        
        // Update the UI
        updateSocketConnectionStatus(isConnected: true)
        
        // Subscribe to the WS Ticker channel
        let tickerChannelWebsocket = BitfinexWSTickerChannel()
        if let tickerSubscriptionMessage = tickerChannelWebsocket.tickerSubscriptionMessage(forSymbol: currencyPair.identifier) {
            socket.write(string: tickerSubscriptionMessage)
        }
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("BitfinexWebSocket is now disconnected: \(String(describing: error?.localizedDescription))")
        
        // Update the UI
        updateSocketConnectionStatus(isConnected: false)
        
        // Alert the user
        var errorMessage = "Socket Disconnected"
        if let anError = error {
            errorMessage = errorMessage + ": \(anError.localizedDescription)"
        }
        let disconnectedAlert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
        disconnectedAlert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        present(disconnectedAlert, animated: true, completion: nil)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("BitfinexWebSocket received some text: \(text)")
        
        let message = BitfinexWSResponseConstructor.websocketMessage(fromJsonString: text)
        
        // -------------
        // INFO MESSAGE
        // -------------
        if message is BFWebsocketInfoMessage {
            // we verify the status of the platform
            let infoMessage = message as! BFWebsocketInfoMessage
            if !infoMessage.platformIsOperative {
                // If the platform is not operative, we disconnect
                socket.disconnect()
            }
        }
        
        // -------------
        // ERROR MESSAGE
        // -------------
        if message is BFWebsocketErrorMessage {
            // we log the error and disconnect
            let errorMessage = message as! BFWebsocketErrorMessage
            print("!!!! An error occurred! Error code: \(errorMessage.errorCode), error message: \(errorMessage.errorMessage ?? "no message") !!!!")
            socket.disconnect()
        }

        // -------------
        // HEARTHBEAT MESSAGE
        // -------------
        if message is BFWebsocketHBMessage {
            // nothing to do
            let hearthbeatMessage = message as! BFWebsocketHBMessage
            print("Heartbeat message for channel \(hearthbeatMessage.channelId)")
        }
        
        // -------------
        // TICKER CHANNEL SUBSCRIPTION MESSAGE
        // -------------
        if message is BFWebsocketTickerSubscriptionMessage {
            // we store the channel id to use it later to detect other messages from this channel
            let tickerSubscriptionMessage = message as! BFWebsocketTickerSubscriptionMessage
            print("Subscribed to channel \(BFWebsocketTickerSubscriptionMessage.channelName)")
            tickerChannelId = tickerSubscriptionMessage.channelId
        }

        // -------------
        // TICKER CHANNEL UPDATE MESSAGE
        // -------------
        if message is BFWebsocketTickerUpdateMessage {
            // we use the ticker update message to update the UI
            let tickerUpdateMessage = message as! BFWebsocketTickerUpdateMessage
            print("Ticker update message for channel \(tickerUpdateMessage.channelId)")
            if tickerUpdateMessage.channelId == tickerChannelId {
                updateTickerUI(withUpdateMessage: tickerUpdateMessage)
            }
        }

    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("BitfinexWebSocket received some data: \(data.count)")
    }
}


// MARK:- UI updates
extension CurrencyPairViewController {
    
    private func updateSocketConnectionStatus(isConnected connected: Bool) {
        socketStatus.text = connected ? "CONNECTED" : "DISCONNECTED"
        socketStatus.textColor = connected ? UIColor(red: 137.0/255, green: 196.0/255, blue: 79.0/255, alpha: 1) : UIColor.red
    }
    
    private func updateTickerUI(withUpdateMessage tickerUpdateMessage: BFWebsocketTickerUpdateMessage) {
        self.lastPriceLabel.text = "LAST: $\(tickerUpdateMessage.lastPrice)"
        self.highPriceLabel.text = "HIGH: $\(tickerUpdateMessage.dailyHigh)"
        self.lowPriceLabel.text = "LOW: $\(tickerUpdateMessage.dailyLow)"
        self.volumeLabel.text = "VOL: \(tickerUpdateMessage.volume)"
        self.percentage24HoursLabel.text = "\(tickerUpdateMessage.dailyChangePercentage * 100) %"
        
        if tickerUpdateMessage.dailyChangePercentage >= 0 {
            self.percentage24HoursLabel.textColor = UIColor.green
        } else {
            self.percentage24HoursLabel.textColor = UIColor.red
        }
    }
}

//MARK: - Segmented Control
extension CurrencyPairViewController {
    
    @objc private func segmentedControlValueChanged(sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            print("ORDER BOOK")
        } else {
            print("TRADES")
        }
    }
}


//MARK: - TableView datasource and delegate
extension CurrencyPairViewController: UITableViewDataSource, UITableViewDelegate {
   
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let reuseIdentifier = "ReuseIdentifier"
        
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        cell.textLabel?.text = ""
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    }

}








