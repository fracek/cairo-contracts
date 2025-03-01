%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import call_contract, get_caller_address
from starkware.starknet.common.storage import Storage

#
# Structs
#

struct Message:
    member to: felt
    member selector: felt
    member calldata: felt*
    member calldata_size: felt
    member this: felt
    member nonce: felt
end

#
# Storage
#

@storage_var
func current_nonce() -> (res: felt):
end

@storage_var
func public_key() -> (res: felt):
end

@storage_var
func initialized() -> (res: felt):
end

@storage_var
func address() -> (res: felt):
end

#
# Guards
#

@view
func assert_only_self{
        storage_ptr: Storage*,
        pedersen_ptr: HashBuiltin*,
        syscall_ptr: felt*,
        range_check_ptr
    }():
    let (self) = address.read()
    let (caller) = get_caller_address()
    assert self = caller
    return ()
end

@view
func assert_initialized{
        storage_ptr: Storage*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }():
    let (_initialized) = initialized.read()
    assert _initialized = 1
    return ()
end

#
# Getters
#

@external
func get_public_key{ storage_ptr: Storage*, pedersen_ptr: HashBuiltin*, range_check_ptr }() -> (res: felt):
    let (res) = public_key.read()
    return (res=res)
end

@external
func get_address{ storage_ptr: Storage*, pedersen_ptr: HashBuiltin*, range_check_ptr }() -> (res: felt):
    let (res) = address.read()
    return (res=res)
end

@external
func get_nonce{ storage_ptr: Storage*, pedersen_ptr: HashBuiltin*, range_check_ptr }() -> (res: felt):
    let (res) = current_nonce.read()
    return (res=res)
end

#
# Setters
#

@external
func set_public_key{
        storage_ptr: Storage*,
        pedersen_ptr: HashBuiltin*,
        syscall_ptr: felt*,
        range_check_ptr
    }(new_public_key: felt):
    assert_only_self()
    public_key.write(new_public_key)
    return ()
end

#
# Initializer
#

@external
func initialize{
        storage_ptr: Storage*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (_public_key: felt, _address: felt):
    let (_initialized) = initialized.read()
    assert _initialized = 0
    initialized.write(1)
    public_key.write(_public_key)
    address.write(_address)
    return ()
end

#
# Business logic
#

@view
func is_valid_signature{
        storage_ptr: Storage*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        syscall_ptr: felt*,
        range_check_ptr
    } (
        hash: felt,
        signature_len: felt,
        signature: felt*
    ) -> ():
    assert_initialized()
    let (_public_key) = public_key.read()
    # This interface expects a signature pointer and length to make
    # no assumption about signature validation schemes.
    # But this implementation does, and it expects a (sig_r, sig_s) pair.
    let sig_r = signature[0]
    let sig_s = signature[1]

    verify_ecdsa_signature(
        message=hash,
        public_key=_public_key,
        signature_r=sig_r,
        signature_s=sig_s)

    return ()
end

@external
func execute{
        storage_ptr: Storage*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        syscall_ptr: felt*,
        range_check_ptr
    } (
        to: felt,
        selector: felt,
        calldata_len: felt,
        calldata: felt*,
        signature_len: felt,
        signature: felt*
    ) -> (response : felt):
    alloc_locals
    assert_initialized()

    let (__fp__, _) = get_fp_and_pc()
    let (_address) = address.read()
    let (_current_nonce) = current_nonce.read()

    local storage_ptr : Storage* = storage_ptr
    local range_check_ptr = range_check_ptr
    local _current_nonce = _current_nonce

    local message: Message = Message(
        to,
        selector,
        calldata,
        calldata_size=calldata_len,
        _address,
        _current_nonce
    )

    # validate transaction
    let (hash) = hash_message(&message)
    is_valid_signature(hash, signature_len, signature)

    # bump nonce
    current_nonce.write(_current_nonce + 1)

    # execute call
    let response = call_contract(
        contract_address=message.to,
        function_selector=message.selector,
        calldata_size=message.calldata_size,
        calldata=message.calldata
    )

    return (response=response.retdata_size)
end

func hash_message{pedersen_ptr : HashBuiltin*}(message: Message*) -> (res: felt):
    alloc_locals
    let (res) = hash2{hash_ptr=pedersen_ptr}(message.to, message.selector)
    # we need to make `res` local
    # to prevent the reference from being revoked
    local res = res
    let (res_calldata) = hash_calldata(message.calldata, message.calldata_size)
    let (res) = hash2{hash_ptr=pedersen_ptr}(res, res_calldata)
    let (res) = hash2{hash_ptr=pedersen_ptr}(res, message.this)
    let (res) = hash2{hash_ptr=pedersen_ptr}(res, message.nonce)
    return (res=res)
end

func hash_calldata{pedersen_ptr: HashBuiltin*}(
        calldata: felt*,
        calldata_size: felt
    ) -> (res: felt):
    if calldata_size == 0:
        return (res=0)
    end

    if calldata_size == 1:
        return (res=[calldata])
    end

    let _calldata = [calldata]
    let (res) = hash_calldata(calldata + 1, calldata_size - 1)
    let (res) = hash2{hash_ptr=pedersen_ptr}(res, _calldata)
    return (res=res)
end
