
export class DittoService {
    private isInitialized : boolean; 

    constructor() {
        this.isInitialized = false;
    }

    public getInitializationStatus(): boolean {
        return this.isInitialized;
    }
}