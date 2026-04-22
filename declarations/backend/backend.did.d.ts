import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface Category {
  'name' : string,
  'description' : string,
  'image' : [] | [string],
}
export interface CheckoutLineItem { 'product_id' : bigint, 'quantity' : bigint }
export interface PaginationResult {
  'currentPage' : bigint,
  'items' : Array<Product>,
  'totalPages' : bigint,
  'totalItems' : bigint,
  'hasNextPage' : boolean,
  'hasPrevPage' : boolean,
}
export interface PaginationResult_1 {
  'currentPage' : bigint,
  'items' : Array<Category>,
  'totalPages' : bigint,
  'totalItems' : bigint,
  'hasNextPage' : boolean,
  'hasPrevPage' : boolean,
}
export interface Product {
  'id' : bigint,
  'name' : string,
  'description' : string,
  'category' : string,
  'image' : [] | [string],
  'price' : bigint,
}
export type Status = {
    'completed' : { 'userPrincipal' : [] | [string], 'response' : string }
  } |
  { 'checking' : { 'userPrincipal' : [] | [string] } } |
  { 'failed' : { 'error' : string, 'userPrincipal' : [] | [string] } };
export interface _SERVICE {
  'addAdmin' : ActorMethod<[Principal], undefined>,
  'addAllowedOrigin' : ActorMethod<[string], string>,
  'addCategory' : ActorMethod<[string, string, [] | [string]], undefined>,
  'addProduct' : ActorMethod<
    [string, string, bigint, string, [] | [string]],
    undefined
  >,
  'addTransaction' : ActorMethod<[string], [] | [Status]>,
  'clearAllCategories' : ActorMethod<[], string>,
  'clearAllProducts' : ActorMethod<[], string>,
  'clearAllTransactions' : ActorMethod<[], string>,
  'createCheckoutSession' : ActorMethod<
    [Array<CheckoutLineItem>, string, string],
    string
  >,
  'deleteCategory' : ActorMethod<[string], undefined>,
  'deleteProduct' : ActorMethod<[bigint], undefined>,
  'deleteTransaction' : ActorMethod<[string], boolean>,
  'editProduct' : ActorMethod<
    [bigint, string, string, bigint, string, [] | [string]],
    undefined
  >,
  'getAdmins' : ActorMethod<[], Array<Principal>>,
  'getAllCategories' : ActorMethod<[], Array<string>>,
  'getAllowedOrigins' : ActorMethod<[], Array<string>>,
  'getCategories' : ActorMethod<
    [[] | [bigint], [] | [bigint]],
    PaginationResult_1
  >,
  'getProducts' : ActorMethod<[[] | [bigint], [] | [bigint]], PaginationResult>,
  'getProductsByCategory' : ActorMethod<
    [string, [] | [bigint], [] | [bigint]],
    PaginationResult
  >,
  'getTransaction' : ActorMethod<[string], [] | [Status]>,
  'getTransactionLineItems' : ActorMethod<[string, [] | [string]], string>,
  'getTransactions' : ActorMethod<[], Array<[string, Status]>>,
  'getTransactionsByPrincipal' : ActorMethod<[], Array<[string, Status]>>,
  'getUser' : ActorMethod<[], [] | [string]>,
  'initializeAuth' : ActorMethod<[], undefined>,
  'initializeData' : ActorMethod<
    [Array<Category>, Array<Product>, Array<string>],
    string
  >,
  'isAdmin' : ActorMethod<[], boolean>,
  'removeAdmin' : ActorMethod<[Principal], undefined>,
  'removeAllowedOrigin' : ActorMethod<[string], string>,
  'setAuthorization' : ActorMethod<[string], undefined>,
  'setUser' : ActorMethod<[string], undefined>,
  'transform' : ActorMethod<
    [
      {
        'response' : {
          'status' : bigint,
          'body' : Uint8Array | number[],
          'headers' : Array<{ 'value' : string, 'name' : string }>,
        },
      },
    ],
    {
      'status' : bigint,
      'body' : Uint8Array | number[],
      'headers' : Array<{ 'value' : string, 'name' : string }>,
    }
  >,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
