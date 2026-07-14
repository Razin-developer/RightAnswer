import { Injectable } from "@nestjs/common";

import { LocalStorageAdapter } from "@right-answer/storage";

@Injectable()
export class StorageService {
  readonly adapter = new LocalStorageAdapter();
}
