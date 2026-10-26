// Jest stand-in for lightning/uiLayoutApi (sfdx-lwc-jest doesn't ship one):
// getLayout as a test wire adapter, so tests can emit layouts.
import { createLdsTestWireAdapter } from "@salesforce/sfdx-lwc-jest";

export const getLayout = createLdsTestWireAdapter(jest.fn());
