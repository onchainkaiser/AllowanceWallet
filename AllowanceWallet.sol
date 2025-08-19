// SPDX-License-Identifier: MIT
pragma solidity  ^0.8.24;

/// @notice minimal ERC20 interface 
interface IERC20 {
    function transfer(address to, uint256 amount) external returns(bool);
    function transferFrom(address from, address to, uint256 amount) external returns(bool) ;
    function balanceOf (address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// title AllowanceWallet (v0.1) - parents sets per-period token allowance kids can self claim
contract AllowanceWallet{
    //----roles----
    address public parent;

    // ----config----
    IERC20 public immutable token;
    uint256 public immutable periodDuration;

    //----data----
    struct ChildAllowance{
        uint256 allowancePerPeriod;
        uint256 spentInperiod;
        uint256 periodStart;
        bool exists;
    }
    mapping (address => ChildAllowance) public children;

    //----events----
    event Funded(address indexed from, uint256 amount);
    event AllowanceSet(address indexed child, uint256 amountPerPeriod);
    event Claimed(address indexed child, uint256 amount);
    event Revoked(address indexed child);

    //----modifiers----
    modifier onlyParent(){
        require(msg.sender == parent, "not-parent");
        _;
    }

    constructor(IERC20 _token, uint256 _periodDurationSeconds, address _parent) {
        require(address(_token) != address(0), "token=zero");
        require(_periodDurationSeconds > 0, "period=zero");
        require(_parent !=address(0), "parent=zero");
        token = _token;
        periodDuration = _periodDurationSeconds;
        parent = _parent;
    }

    // --------parent actions------

    /// @notice pull tokens from parent into this wallet (parent must approve first)
    function fund(uint256 amount) external onlyParent{
        require(amount > 0, "amount = 0");
        bool ok = token.transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom failed");
        emit Funded(msg.sender, amount);
    }
    ///@notice set or update a child allowance per period
    function setAllowance(address child, uint256 amountPerPeriod) external onlyParent{
        require(child != address(0), "child=zero");
        ChildAllowance storage ca = children[child];
        if (!ca.exists) {
            ca.exists = true;
            ca.periodStart = block.timestamp; // start windows now 
        }

        ca.allowancePerPeriod = amountPerPeriod;
        emit AllowanceSet(child, amountPerPeriod);
    }

    /// @notice remove child from program
    function revoke(address child) external onlyParent {
        require(children[child].exists, "not-child");
        delete children[child];
        emit Revoked(child);
    }

    //------ views -------

    /// @notice how much the child can still claim in the current window
    function avaliable(address child) public view returns (uint256) {
        ChildAllowance storage ca = children[child];
        if (!ca.exists) return 0;

        // if window expired, fulll allowance is available nextt claim
        if (block.timestamp >= ca.periodStart + periodDuration) {
            return ca.allowancePerPeriod;
        }

        if (ca.spentInperiod >= ca.allowancePerPeriod) return 0;
        return ca.allowancePerPeriod - ca.spentInperiod;
    }

    // ------- kid action -----

    /// @notice child claims tokens to them self with their cap (auto-resets period if elapsed)
    function claim(uint256 amount) external {
        ChildAllowance storage ca = children[msg.sender];
        require(ca.exists, "not-child");
        require(amount > 0, "amount=0");

        // reset window if period passed
        if (block.timestamp>= ca.periodStart + periodDuration) {
            ca.periodStart = block.timestamp;
            ca.spentInperiod = 0;
        }

        uint256 can = avaliable(msg.sender);
        require(amount <= can, "exceeds-allowance");

        // CEI: effects before interaction
        ca.spentInperiod += amount;

        bool ok = token.transfer(msg.sender, amount);
        require(ok, "transfer failed");

        emit Claimed(msg.sender, amount);
    }

}
