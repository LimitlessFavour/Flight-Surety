pragma solidity ^0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    uint8 private constant M = 4; //No of active airlines required before consensus


    address private contractOwner;          // Account used to deploy contract
    address dataContractAddress;
    bool private operational = true;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;        
        address airline;
        string name;
    }

    FlightSuretyData flightSuretyData;
    mapping(bytes32 => Flight) private flights;

    bytes32[] private flightKeys;


  /********************************************************************************************/
    /*                                       EVENTS                                           */
    /********************************************************************************************/
    event AirlineCreated(address airline);
    event AirlineRegistered(address airline);
    event AirlineActive(address airline);

    event FlightStatusProcessed(address airline, string flight, uint8 statusCode);

    event InsuranceBought(address passenger, bytes32 flightKey);

 
    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
         // Modify to call data contract's status
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

     modifier onlyRegisteredAirlines()
    {
        require(flightSuretyData.getAirlineState(msg.sender) == 1, "Only registered airlines can perform this oepration");
        _;
    }

      modifier onlyActiveAirlines()
    {
        require(flightSuretyData.getAirlineState(msg.sender) == 2, "Only active airlines can perform this oepration");
        _;
    }

  

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor
                                (
                                   address contractAddress //data contract address
                                ) 
                                public 
    {
        contractOwner = msg.sender;
        dataContractAddress = contractAddress;
        flightSuretyData = FlightSuretyData(dataContractAddress);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;  // Modify to call data contract's status
    }

     function setOperatingStatus (bool mode) external requireContractOwner
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

  
   /**
    * @dev Add an airline to the registration queue
    *
    */   
    function registerAirline
                            (   
                                string airlineName
                            )
                            external
                            returns(bool success, uint256 votes)
    {
        flightSuretyData.registerAirline(msg.sender, 0, airlineName);
        emit AirlineCreated(msg.sender);
        return (success, 0);
    }
     /**
    * @dev Approve airline registration after creation - creating the airline.
    *
    */  
       function approveAirlineRegistration
                            (   
                                address airline
                            )
                            external
                            onlyActiveAirlines
                            returns(bool success, uint256 votes)
    {
        require(flightSuretyData.getAirlineState(airline) == 0, "This airline hasn't been created");
        uint256 activeAirlines = flightSuretyData.getActiveAirlines();
        if(activeAirlines < M){ //No consensus required.

          flightSuretyData.updateAirlineState(airline, 1);
          emit AirlineRegistered(airline);

          return(true,0);

        }else{ 
           //consensus required.
           uint8 approvals = flightSuretyData.approveAirlineRegistration(airline, msg.sender);
           if (approvals >= activeAirlines / 2) {

               flightSuretyData.updateAirlineState(airline, 1);
               emit AirlineRegistered(airline);

               return(true,approvals);
            }
        }

    } 
     /**
    * @dev Make airline active by paying.
    *
    */  
      function payAirlineFee
                            (   
                            )
                            external
                            payable
                            onlyRegisteredAirlines
    {
        require(msg.value == 10 ether, "You must pay 10 ether to complete");

        dataContractAddress.transfer(msg.value);
        flightSuretyData.updateAirlineState(msg.sender, 2);

        emit AirlineActive(msg.sender);
    }

   /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight
                                (
                                    uint8 status,
                                    string flight
                                )
                                external
                                onlyActiveAirlines
    {
     bytes32 flightKey = getFlightKey(msg.sender, flight, now);

        flights[flightKey] = Flight(true,status, now, msg.sender, flight);
        flightKeys.push(flightKey);
    }
    
   /**
    * @dev Called after oracle has updated flight status
    *
    */  
    function processFlightStatus
                                (
                                    address airline,
                                    string memory flight,
                                    uint256 timestamp,
                                    uint8 statusCode
                                )
                                internal
    {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        flights[flightKey].statusCode = statusCode;

        emit FlightStatusProcessed(airline, flight, statusCode);
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus
                        (
                            address airline,
                            string flight,
                            uint256 timestamp                            
                        )
                        external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
                                                requester: msg.sender,
                                                isOpen: true
                                            });

        emit OracleRequest(index, airline, flight, timestamp);
    } 


    function getFlightKey
                        (
                            address airline,
                            string flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }


    function getFlightsCount(

                            ) 
                            external 
                            view 
                            returns(uint256 count)
    {
        return flightKeys.length;
    }
    
    function buyInsurance(address airline, string flight, uint256 timestamp)
    external payable
    {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);

        require(bytes(flights[flightKey].name).length > 0, "Flight does not exist");

        require(msg.value <= 1 ether, "Maximum amount is 1 ether");

        dataContractAddress.transfer(msg.value);

        uint256 payoutAmount = msg.value.mul(3).div(2);

        flightSuretyData.createInsurance(msg.sender, flight, msg.value, payoutAmount);

        emit InsuranceBought(msg.sender, flightKey);
    }






// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;    

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle
                            (
                            )
                            external
                            payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
    }

    function getMyIndexes
                            (
                            )
                            view
                            external
                            returns(uint8[3])
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
                        (
                            uint8 index,
                            address airline,
                            string flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }



    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
                            (                       
                                address account         
                            )
                            internal
                            returns(uint8[3])
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);
        
        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
                            (
                                address account
                            )
                            internal
                            returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion

}   


/********************************************************************************************/
/*                               DATA CONTRACT INTERFACE                                    */
/********************************************************************************************/

contract FlightSuretyData {
    function getAirlineState(
                                address airline
                            )
                            view
                            returns(uint)
    {
        return 1;
    }

    function registerAirline(
                            address airlineAddress,
                            uint8 state,
                            string name
                            )
                            view
    {

    }

    function updateAirlineState
                                (
                                address airlineAddress,
                                uint8 state
                                )
                                view
    {

    }

    function getActiveAirlines(
                              ) 
                              view 
                              returns(uint)
    {
        return 1;
    }

    function approveAirlineRegistration(
                                        address airline, 
                                        address approver
                                        )
                                        view
                                        returns (uint8)
    {
        return 1;
    }

    function createInsurance(
                            address passenger, 
                            string flight, 
                            uint256 amount, 
                            uint256 payoutAmount
                            )
                            view
    {

    }

    function getInsurance(
                         address passenger, 
                         string flight
                         )
                         view
                         returns 
                         (
                         uint256 amount, 
                         uint256 payoutAmount, 
                         uint256 state
                         )
    {
        amount = 1;
        payoutAmount = 1;
        state = 1;
    }

    function  claimInsurance
                           (
                            address passenger, 
                            string flight
                            )
                            view
    {

    }

    function getPassengerBalance
                                (
                                address passenger
                                )
                                view
                                returns 
                                (
                                uint256
                                )
    {
        return 1;
    }

    function payPassenger
                        (address passenger
                        )
                        view
    {

    }

}