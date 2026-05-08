import { LightningElement, api, track } from 'lwc';

export default class LnchatDrawer extends LightningElement {
    @api showIntentBadge = false;
    @track isOpen = false;

    get drawerClass() {
        return 'drawer-container' + (this.isOpen ? ' is-open' : '');
    }

    get triggerClass() {
        return 'drawer-trigger' + (this.isOpen ? ' trigger-open' : '');
    }

    get triggerIcon() {
        return this.isOpen ? 'utility:close' : 'utility:einstein';
    }

    handleToggle() {
        this.isOpen = !this.isOpen;
    }

    handleClose() {
        this.isOpen = false;
    }
}
