from .utilities import get_account, get_contract
from brownie import mantraCampaign, network, config, accounts
import time


def deploy_mantraCampaign():
    print("Deploying contracts...")
    account = get_account()
    Campaign = mantraCampaign.deploy(
        get_contract("eth_usd_price_feed").address,
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify", False),
    )
    print(f"Deployed contract mantraCampaign in {network.show_active()} network")
    return Campaign


def main():
    deploy_mantraCampaign()
