import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer

signer = Signer(123456789987654321)
L1_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984
ANOTHER_ADDRESS = 0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def account_factory():
    starknet = await Starknet.empty()
    registry = await starknet.deploy("contracts/AddressRegistry.cairo")
    account = await starknet.deploy("contracts/Account.cairo")
    await account.initialize(signer.public_key, account.contract_address).invoke()
    return starknet, account, registry


@pytest.mark.asyncio
async def test_set_address(account_factory):
    _, account, registry = account_factory

    await signer.send_transaction(account, registry.contract_address, 'set_L1_address', [L1_ADDRESS])
    assert await registry.get_L1_address(account.contract_address).call() == (L1_ADDRESS,)


@pytest.mark.asyncio
async def test_update_address(account_factory):
    _, account, registry = account_factory

    await signer.send_transaction(account, registry.contract_address, 'set_L1_address', [L1_ADDRESS])
    assert await registry.get_L1_address(account.contract_address).call() == (L1_ADDRESS,)

    await signer.send_transaction(account, registry.contract_address, 'set_L1_address', [ANOTHER_ADDRESS])
    assert await registry.get_L1_address(account.contract_address).call() == (ANOTHER_ADDRESS,)
