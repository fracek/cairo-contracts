import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer

signer = Signer(123456789987654321)


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def erc20_factory():
    starknet = await Starknet.empty()
    erc20 = await starknet.deploy("contracts/token/ERC20.cairo")
    account = await starknet.deploy("contracts/Account.cairo")
    await account.initialize(signer.public_key, account.contract_address).invoke()
    await signer.send_transaction(account, erc20.contract_address, 'initialize', [])
    return starknet, erc20, account


@pytest.mark.asyncio
async def test_initializer(erc20_factory):
    _, erc20, account = erc20_factory
    assert await erc20.balance_of(account.contract_address).call() == (1000,)
    assert await erc20.get_total_supply().call() == (1000,)


@pytest.mark.asyncio
async def test_transfer(erc20_factory):
    _, erc20, account = erc20_factory
    recipient = 123
    amount = 100
    (previous_supply,) = await erc20.get_total_supply().call()
    assert await erc20.balance_of(account.contract_address).call() == (1000,)
    assert await erc20.balance_of(recipient).call() == (0,)
    await signer.send_transaction(account, erc20.contract_address, 'transfer', [recipient, amount])
    assert await erc20.balance_of(account.contract_address).call() == (900,)
    assert await erc20.balance_of(recipient).call() == (100,)
    assert (previous_supply,) == await erc20.get_total_supply().call()


@pytest.mark.asyncio
async def test_insufficient_sender_funds(erc20_factory):
    _, erc20, account = erc20_factory
    recipient = 123
    (balance,) = await erc20.balance_of(account.contract_address).call()

    try:
        await signer.send_transaction(account, erc20.contract_address, 'transfer', [recipient, balance + 1])
        assert False
    except StarkException as err:
        _, error = err.args
        assert error['code'] == StarknetErrorCode.TRANSACTION_FAILED


@pytest.mark.asyncio
async def test_approve(erc20_factory):
    _, erc20, account = erc20_factory
    spender = 123
    amount = 345
    assert await erc20.allowance(account.contract_address, spender).call() == (0,)
    await signer.send_transaction(account, erc20.contract_address, 'approve', [spender, amount])
    assert await erc20.allowance(account.contract_address, spender).call() == (amount,)


@pytest.mark.asyncio
async def test_transfer_from(erc20_factory):
    starknet, erc20, account = erc20_factory
    spender = await starknet.deploy("contracts/Account.cairo")
    # we use the same signer to control the main and the spender accounts
    # this is ok since they're still two different accounts
    await spender.initialize(signer.public_key, spender.contract_address).invoke()
    amount = 345
    recipient = 987
    (previous_balance,) = await erc20.balance_of(account.contract_address).call()

    await signer.send_transaction(account, erc20.contract_address, 'approve', [spender.contract_address, amount])
    await signer.send_transaction(spender, erc20.contract_address, 'transfer_from', [account.contract_address, recipient, amount])

    assert await erc20.balance_of(account.contract_address).call() == (previous_balance - amount,)
    assert await erc20.balance_of(recipient).call() == (amount,)
    assert await erc20.allowance(account.contract_address, spender.contract_address).call() == (0,)
