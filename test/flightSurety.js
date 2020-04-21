
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');
const truffleAssert = require('truffle-assertions');


contract('Flight Surety Tests', async (accounts) => {

var config;
 const firstAirline = accounts[0];
 const secondAirline = accounts[1];
 const thirdAirline = accounts[2];
 const fourthAirline = accounts[3];
 const fifthAirline = accounts[4];


  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.setAppContractAuthorizationStatus(config.flightSuretyApp.address,true);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let flightSuretyDataStatus = await config.flightSuretyData.isOperational.call();
    let flightSuretyAppStatus = await config.flightSuretyApp.isOperational.call();
    assert.equal(flightSuretyDataStatus, true, "Incorrect initial flightSuretyData operating status value");
    assert.equal(flightSuretyAppStatus, true, "Incorrect initial FlightSuretyApp operating status value");

  });

  it('flightSuretyAppContract is authorised to make calls to flightSuretyData', async function () {
    const status = await config.flightSuretyData.getAppContractAuthorizationStatus(config.flightSuretyApp.address);
    assert.equal(status, true, "AppContract is not authorized");
});

it('First airline(Contract owner) is  active', async function () {
    assert.equal(await config.flightSuretyData.getAirlineState(firstAirline), 2,"First airline");
});

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
            
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
      
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try 
      {
          await config.flightSurety.setTestingMode(true);
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");      

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

  });

  it('Airlines can apply for registration', async function () {
    const registerAirline = await config.flightSuretyApp.registerAirline("Second Airline", { from: secondAirline });
    await config.flightSuretyApp.registerAirline("Third Airline", { from: thirdAirline });


    const appliedState = 0;

    assert.equal(await config.flightSuretyData.getAirlineState(secondAirline), appliedState, "2nd applied airline is of incorrect state");
    assert.equal(await config.flightSuretyData.getAirlineState(thirdAirline), appliedState, "3rd applied airline is of incorrect state");

    truffleAssert.eventEmitted(registerAirline, 'AirlineCreated', (ev) => {
        return ev.airline === secondAirline;
    });
});

it('Active airline can approve other appying airlines', async function () {
    const approveAirlineRegistration = await config.flightSuretyApp.approveAirlineRegistration(secondAirline, { from: firstAirline });
    await config.flightSuretyApp.approveAirlineRegistration(thirdAirline, { from: firstAirline });

    const registeredState = 1;

    assert.equal(await config.flightSuretyData.getAirlineState(secondAirline), registeredState, "2nd registered airline is of incorrect state");
    assert.equal(await config.flightSuretyData.getAirlineState(thirdAirline), registeredState, "3rd registered airline is of incorrect state");

    truffleAssert.eventEmitted(approveAirlineRegistration, 'AirlineRegistered', (ev) => {
        return ev.airline === secondAirline;
    });
});

it('Registered airlines can pay fees', async function () {
    const payAirlineFee = await config.flightSuretyApp.payAirlineFee({ from: secondAirline, value: web3.utils.toWei('10', 'ether') });
    await config.flightSuretyApp.payAirlineFee({ from: thirdAirline, value: web3.utils.toWei('10', 'ether') });

    const paidState = 2;

    assert.equal(await config.flightSuretyData.getAirlineState(secondAirline), paidState, "2nd paid airline is of incorrect state");
    assert.equal(await config.flightSuretyData.getAirlineState(thirdAirline), paidState, "3rd paid airline is of incorrect state");

    truffleAssert.eventEmitted(payAirlineFee, 'AirlineActive', (ev) => {
        return ev.airline === secondAirline;
    });

    const balance = await web3.eth.getBalance(config.flightSuretyData.address);
    const balanceEther = web3.utils.fromWei(balance, 'ether');

    assert.equal(balanceEther, 20, "Wrong amount transferred");
});

  it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {
    
    // ARRANGE
    let newAirline = accounts[2];

    // ACT
    try {
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    }
    catch(e) {

    }
    let result = await config.flightSuretyData.isAirline.call(newAirline); 

    // ASSERT
    assert.equal(result, true, "Airline should not be able to register another airline if it hasn't provided funding");

  });

  it('Multiparty consensus required to approve fifth airline', async function () {

    // A single active airline trying to approve a new airline should fail
    try {
        await config.flightSuretyApp.approveAirlineRegistration(fifthAirline, { from: firstAirline });
    } catch (err) {
        console.log(err);
    }
    assert.equal(await config.flightSuretyData.getAirlineState(fifthAirline), 0, "Single airline should not be able to approve a fifth airline alone");

    // Now,consensus should pass
    const approveAirlineRegistration = await config.flightSuretyApp.approveAirlineRegistration(fifthAirline, { from: secondAirline });
    assert.equal(await config.flightSuretyData.getAirlineState(fifthAirline), 1, "5th registered airline is of incorrect state");

    truffleAssert.eventEmitted(approveAirlineRegistration, 'AirlineRegistered', (ev) => {
        return ev.airline === fifthAirline;
    });
});
 

 //TODO
});
