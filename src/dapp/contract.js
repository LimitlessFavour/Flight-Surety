import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import Config from './config.json';
import Web3 from 'web3';

export default class Contract {
    constructor(network, callback) {

        let config = Config[network];
        this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));
        this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
        this.flightSuretyData = new this.web3.eth.Contract(FlightSuretyData.abi, config.dataAddress);
        this.initialize(callback);
        this.owner = null;
        this.airlines = [];
        this.passengers = [];
    }

    initialize(callback) {
        this.web3.eth.getAccounts((error, accts) => {
           
            this.owner = accts[0];

            let counter = 1;
            
            while(this.airlines.length < 5) {
                this.airlines.push(accts[counter++]);
            }

            while(this.passengers.length < 5) {
                this.passengers.push(accts[counter++]);
            }

            callback();
        });
    }

    authorizeAppContract(callback) {
        let self = this;
        self.flightSuretyData.methods
            .getAppContractAuthorizationStatus(self.config.appAddress)
            .call({ from: self.owner }, (err, isAuthorized) => {

                if (isAuthorized){
                       return callback(isAuthorized);

                } 
                self.flightSuretyData.methods
                    .setAppContractAuthorizationStatus(self.config.appAddress, true)
                    .send({ from: self.owner }, () => {
                        callback(true);
                    });

            });
    }


    isOperational(callback) {
       let self = this;
       self.flightSuretyApp.methods
            .isOperational()
            .call({ from: self.owner}, callback);
    }

      getBalance() {
        let self = this;
        self.flightSuretyApp.methods
                .getBalance()
                .call({ from: self.owner }, async (err, balance) => {
                    resolve(self.web3.utils.fromWei(balance, 'ether'));
                });
    }

    withdrawBalance(callback) {
        let self = this;
            self.flightSuretyApp.methods
                .withdrawBalance()
                .send(
                    { from: self.owner },
                    (err, res) => {
                        if (err){
                            return throw new Error(err);
                        } 
                        return callback(res);
                    }
                 );
    }
}

       getFlights(callback) {
           let self = this;
            self.flightSuretyApp.methods
                .getFlightsCount()
                .call({ from: self.owner }, async (err, count) => {
                    const flights = [];
                    for (var idx = 0; idx < count; idx++) {
                        const res = await this.flightSuretyApp.methods.getFlight(idx).call({ from: this.owner });
                        flights.push(res);
                    }
                   return callback(flights);
                });
    }

    buyInsurance(airline, flight, timestamp, amount, callback) {
        let self = this;
            self.flightSuretyApp.methods
                .buyInsurance(airline, flight, timestamp)
                .send(
                    {from: this.owner, value: this.web3.utils.toWei(amount.toString(), 'ether')},
                    (err, res) => {
                        if (err){
                          return throw new Error(err);
                        } 
                      return callback(res);
                    }
                )
    }

  claimInsurance(airline, flight, timestamp,callback) {
        let self = this;
            self.flightSuretyApp.methods
                .claimInsurance(airline, flight, timestamp)
                .send(
                    { from: self.owner },
                    (err, res) => {
                        if (err) {
                            return throw new Error(err);
                        }
                        callback(res);
                    }
                );
        });
    }

  getPassengerInsurances(flights,callback) {
      let self = this;
        const insurances = [];

        flights.map(async (flight) => {
                const insurance = await self.flightSuretyApp.methods
                    .getInsurance(flight.flight)
                    .call({ from: this.owner });

                if (insurance.amount !== "0"){
                  insurances.push({
                    amount: this.web3.utils.fromWei(insurance.amount, 'ether'),
                    payoutAmount: this.web3.utils.fromWei(insurance.payoutAmount, 'ether'),
                    state: insurance.state,
                    flight: flight
                });
                }
            });
        callback(insurances);
    }

    fetchFlightStatus(flight, callback) {  
        let self = this;
        let payload = {
            airline: self.airlines[0],
            flight: flight,
            timestamp: Math.floor(Date.now() / 1000)
        } 
        self.flightSuretyApp.methods
            .fetchFlightStatus(payload.airline, payload.flight, payload.timestamp)
            .send({ from: self.owner}, (error, result) => {
                callback(error, payload);
            });
    }
}