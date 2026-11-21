import { createContext, createElement, useContext, useState } from 'react'
import type { Dispatch, ReactNode, SetStateAction } from 'react'

type ClientListState = { input: string; query: string; sort: string; page: number }
export const defaultClientList = (): ClientListState => ({ input: '', query: '', sort: 'asc', page: 1 })
const ClientListContext = createContext<[ClientListState, Dispatch<SetStateAction<ClientListState>>] | null>(null)
export function ClientListProvider({ children }: { children: ReactNode }) {
  const state = useState(defaultClientList)
  return createElement(ClientListContext.Provider, { value: state }, children)
}
export function useClientListState() {
  const shared = useContext(ClientListContext)
  const local = useState(defaultClientList)
  return shared ?? local
}
