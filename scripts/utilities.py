from brownie import (
    network,
    accounts,
    config,
    MockV3Aggregator,
    Contract,
)

LOCAL_BLOCKCHAIN_ENVIRONMENTS = ["development", "ganache-local"]
FORKED_LOCAL_ENVIRONMENTS = ["mainnet-fork"]


def get_account():
    if (
        network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS
        or network.show_active() in FORKED_LOCAL_ENVIRONMENTS
    ):
        return accounts[0]

    return accounts.add(config["wallets"]["from_key"])


DECIMALS = 8
INITIAL_VALUE = 200000000000


def deploy_mocks(decimals=DECIMALS, initial_value=INITIAL_VALUE):
    print("deploying mocks")
    account = get_account()
    MockV3Aggregator.deploy(decimals, initial_value, {"from": account})


contract_to_mock = {"eth_usd_price_feed": MockV3Aggregator}


def get_contract(contract_name):
    """This function will grap the contract addresses from the Brownie Config if defined
    Otherwise, it will deploy a mock version of the contract

    Args:
        contract_name : (string)

    Returns:
        brownie.network.contract.ProjectContract: The most recently deployed version of this contract
    """

    contract_type = contract_to_mock[contract_name]
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        if len(contract_type) <= 0:
            deploy_mocks()
        contract = contract_type[-1]
    else:
        contract_address = config["networks"][network.show_active()][contract_name]
        contract = Contract.from_abi[
            contract_type._name, contract_address, contract_type.abi
        ]
    return contract
